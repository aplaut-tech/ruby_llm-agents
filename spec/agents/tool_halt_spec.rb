# frozen_string_literal: true

require "rails_helper"

# Drives a real RubyLLM::Chat tool loop (only the provider request is
# stubbed) to check how Tool#halt ends an agent run on RubyLLM 2.
RSpec.describe "Tool#halt ending the agent's tool loop" do
  let(:lookup_tool) do
    Class.new(RubyLLM::Agents::Tool) do
      def self.name
        "LookupTool"
      end

      description "Looks things up"
      parameter :query, description: "What to look up"

      def execute(query:)
        "found #{query}"
      end
    end
  end

  let(:halting_tool) do
    Class.new(RubyLLM::Agents::Tool) do
      def self.name
        "BudgetTool"
      end

      description "Stops the loop once the budget is spent"
      parameter :query, description: "What to look up"

      def execute(query:)
        halt("Budget spent, answer from what you have")
        "not reached"
      end
    end
  end

  let(:agent_class) do
    tools_list = [lookup_tool, halting_tool]
    Class.new(RubyLLM::Agents::Base) do
      def self.name
        "HaltingAgent"
      end

      model "gpt-4o-mini"
      system "Use the tools."
      user "{question}"
      tools(*tools_list)
    end
  end

  let(:llm) { RubyLLM.context { |config| config.openai_api_key = "test-key" } }
  let(:chat) { llm.chat(model: "gpt-4o-mini", provider: :openai, assume_model_exists: true) }

  def tool_call_response(call_id, tool_class, input:, output:, cache_read: nil)
    RubyLLM::Message.new(
      role: :assistant,
      content: "",
      model: "gpt-4o-mini-2024-07-18",
      tool_calls: {
        call_id => RubyLLM::ToolCall.new(id: call_id, name: tool_class.new.name, arguments: {"query" => "x"})
      },
      input_tokens: input,
      output_tokens: output,
      cache_read_tokens: cache_read,
      finish_reason: :tool_calls
    )
  end

  before do
    stub_agent_configuration(track_executions: true, async_logging: false)
    allow(RubyLLM).to receive(:chat).and_return(chat)
    allow_any_instance_of(RubyLLM::Providers::OpenAI).to receive(:complete).and_return(
      tool_call_response("call_1", lookup_tool, input: 100, output: 20, cache_read: 40),
      tool_call_response("call_2", halting_tool, input: 150, output: 30)
    )
  end

  it "returns the halt message as the result content" do
    result = agent_class.call(question: "What happened?")

    expect(result).to be_success
    expect(result.content).to eq("Budget spent, answer from what you have")
    expect(result.finish_reason).to eq("halt")
  end

  it "stops calling the model once a tool halts" do
    agent_class.call(question: "What happened?")

    expect(chat.messages.count { |message| message.role == :assistant }).to eq(2)
  end

  it "sums the usage of every round billed before the halt" do
    result = agent_class.call(question: "What happened?")

    expect(result.input_tokens).to eq(250)
    expect(result.output_tokens).to eq(50)
    expect(result.cached_tokens).to eq(40)
    expect(result.total_cost).to be > 0
  end

  it "records the execution as a success with the halt finish reason" do
    agent_class.call(question: "What happened?")

    execution = RubyLLM::Agents::Execution.last
    expect(execution.status).to eq("success")
    expect(execution.finish_reason).to eq("halt")
    expect(execution.input_tokens).to eq(250)
    expect(execution.metadata["llm_usage"]).to include("requests" => 2, "last_input_tokens" => 150)
  end

  it "completes the halted call's ToolExecution instead of leaving it running" do
    agent_class.call(question: "What happened?")

    records = RubyLLM::Agents::ToolExecution.order(:id)
    expect(records.map(&:status)).to eq(%w[success success])
    expect(records.last.output).to eq("Budget spent, answer from what you have")
  end

  it "tracks the halted call with the agent's tool calls" do
    agent_class.call(question: "What happened?")

    tool_calls = RubyLLM::Agents::Execution.last.detail.tool_calls
    expect(tool_calls.map { |call| call["name"] }).to eq([lookup_tool.new.name, halting_tool.new.name])
    expect(tool_calls.last).to include("status" => "success", "result" => "Budget spent, answer from what you have")
  end

  it "emits a tool_end event for the halted call" do
    streaming_agent = Class.new(agent_class) { streaming true }
    events = []
    streaming_agent.call(question: "What happened?", stream_events: true) { |event| events << event }

    tool_events = events.select(&:tool_event?)
    expect(tool_events.map(&:type)).to eq(%i[tool_start tool_end tool_start tool_end])
    expect(tool_events.last.data).to include(tool_name: halting_tool.new.name, status: "success")
  end
end
