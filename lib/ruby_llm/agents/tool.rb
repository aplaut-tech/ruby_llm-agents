# frozen_string_literal: true

require "timeout"

module RubyLLM
  module Agents
    # Base class for tools that need access to the agent's execution context.
    #
    # Inherits from RubyLLM::Tool and adds:
    # - `context` accessor: read agent params, tenant, execution ID
    # - `timeout` DSL: per-tool timeout in seconds
    # - Error handling: exceptions become error strings for the LLM
    # - Tool execution tracking: records each tool call in the database
    # - `halt`: ends the agent's tool loop with a final message
    #
    # Users implement `execute()` — the standard RubyLLM convention.
    # This class overrides `call()` to wrap execution with its features.
    #
    # @example Defining a tool
    #   class BashTool < RubyLLM::Agents::Tool
    #     description "Run a shell command"
    #     timeout 30
    #
    #     parameter :command, description: "The command to run", required: true
    #
    #     def execute(command:)
    #       context.container_id  # reads agent param
    #       # ... run command ...
    #     end
    #   end
    #
    # @example Stopping the loop
    #   def execute(query:)
    #     return halt("Search quota used up, answer from what you have") if quota.exhausted?
    #     # ...
    #   end
    #
    # @example Using with an agent
    #   class CodingAgent < ApplicationAgent
    #     param :container_id, required: true
    #     tools BashTool
    #   end
    #
    #   CodingAgent.call(query: "list files", container_id: "abc123")
    #
    class Tool < RubyLLM::Tool
      # Raised by #halt to end the agent's tool loop.
      #
      # RubyLLM 2 has no way for a tool result to stop the loop, so halting
      # unwinds it instead: the agent catches the Halt and finishes with its
      # #content as the result, keeping the usage of the rounds already
      # billed. Let it propagate — a tool that rescues StandardError around
      # #halt swallows the signal.
      class Halt < RubyLLM::Agents::Error
        # @return [Object] The final content the agent returns
        attr_reader :content

        # @param content [Object] The final content the agent returns
        def initialize(content)
          @content = content
          super(content.to_s)
        end
      end

      # The execution context, set before each call.
      # Provides access to agent params, tenant, execution ID.
      #
      # @return [ToolContext, nil]
      attr_reader :context

      class << self
        # Sets or gets the per-tool timeout in seconds.
        #
        # @param value [Integer, nil] Timeout in seconds (setter)
        # @return [Integer, nil] The configured timeout (getter)
        def timeout(value = nil)
          if value
            @timeout = value
          else
            @timeout
          end
        end
      end

      # Ends the agent's tool loop: the agent stops calling the model and
      # returns +content+ as its result. Raises Halt, so nothing after the
      # call runs.
      #
      # @param content [Object] The final content the agent returns
      # @raise [Halt] Always
      def halt(content)
        raise Halt.new(content)
      end

      # Wraps RubyLLM's call() with context, timeout, tracking, and error handling.
      #
      # RubyLLM's Chat calls tool.call(**arguments, tool_call:) during the
      # tool loop. We set up context, create a tracking record, apply
      # timeout, then delegate to super (which validates args and calls
      # execute).
      #
      # @param tool_call [RubyLLM::ToolCall, nil] The call being executed
      # @param args [Hash] Tool arguments from the LLM
      # @return [Object] The tool result
      # @raise [Halt] When the tool halts the loop
      def call(tool_call: nil, **args)
        pipeline_context = Thread.current[:ruby_llm_agents_caller_context]
        @context = pipeline_context ? ToolContext.new(pipeline_context) : nil

        record = start_tool_tracking(pipeline_context, args)

        check_cancelled!(pipeline_context)

        timeout_seconds = self.class.timeout
        timeout_seconds ||= RubyLLM::Agents.configuration.default_tool_timeout

        result = if timeout_seconds
          Timeout.timeout(timeout_seconds) { super(tool_call: tool_call, **args) }
        else
          super
        end

        complete_tool_tracking(record, result, status: "success")
        result
      rescue Halt => e
        complete_tool_tracking(record, e.content, status: "success")
        raise # Let the halt end the loop in BaseAgent
      rescue Timeout::Error
        complete_tool_tracking(record, nil, status: "timed_out", error: "Timed out after #{timeout_seconds}s")
        "TIMEOUT: Tool did not complete within #{timeout_seconds}s."
      rescue RubyLLM::Agents::CancelledError
        complete_tool_tracking(record, nil, status: "cancelled")
        raise # Let cancellation propagate to BaseAgent
      rescue => e
        complete_tool_tracking(record, nil, status: "error", error: e.message)
        "ERROR (#{e.class}): #{e.message}"
      end

      private

      # Creates a "running" ToolExecution record before the tool runs.
      # Silently skips if no execution_id or ToolExecution is not available.
      #
      # @param pipeline_context [Pipeline::Context, nil]
      # @param args [Hash] The tool arguments
      # @return [ToolExecution, nil]
      def start_tool_tracking(pipeline_context, args)
        return nil unless pipeline_context&.execution_id
        return nil unless defined?(ToolExecution)

        @tool_iteration = (@tool_iteration || 0) + 1

        ToolExecution.create!(
          execution_id: pipeline_context.execution_id,
          tool_name: name,
          iteration: @tool_iteration,
          status: "running",
          input: normalize_input(args),
          started_at: Time.current
        )
      rescue => e
        # Don't let tracking failures break tool execution
        Rails.logger.debug("[RubyLLM::Agents::Tool] Tracking failed: #{e.message}") if defined?(Rails) && Rails.logger
        nil
      end

      # Updates the ToolExecution record after the tool completes.
      #
      # @param record [ToolExecution, nil]
      # @param result [Object, nil] The tool result
      # @param status [String] Final status
      # @param error [String, nil] Error message
      def complete_tool_tracking(record, result, status:, error: nil)
        return unless record

        completed_at = Time.current
        duration_ms = record.started_at ? ((completed_at - record.started_at) * 1000).to_i : nil
        output_str = result.to_s

        record.update!(
          status: status,
          output: truncate_output(output_str),
          output_bytes: output_str.bytesize,
          error_message: error,
          completed_at: completed_at,
          duration_ms: duration_ms
        )
      rescue => e
        Rails.logger.debug("[RubyLLM::Agents::Tool] Tracking update failed: #{e.message}") if defined?(Rails) && Rails.logger
      end

      def check_cancelled!(pipeline_context)
        return unless pipeline_context
        on_cancelled = pipeline_context[:on_cancelled]
        return unless on_cancelled.respond_to?(:call)
        raise CancelledError, "Execution cancelled" if on_cancelled.call
      end

      def normalize_input(args)
        return {} if args.nil?
        args.respond_to?(:to_h) ? args.to_h : {}
      end

      def truncate_output(str)
        max = RubyLLM::Agents.configuration.try(:tool_result_max_length) || 10_000
        (str.length > max) ? str[0, max] + "... (truncated)" : str
      end
    end
  end
end
