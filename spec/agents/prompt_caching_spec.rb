# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Anthropic prompt caching" do
  before do
    stub_agent_configuration(track_executions: false)
  end

  describe "DSL: .cache_prompts" do
    it "defaults to false" do
      klass = Class.new(RubyLLM::Agents::Base)
      expect(klass.cache_prompts).to be false
    end

    it "can be enabled" do
      klass = Class.new(RubyLLM::Agents::Base) { cache_prompts true }
      expect(klass.cache_prompts).to be true
    end

    it "can be explicitly disabled" do
      klass = Class.new(RubyLLM::Agents::Base) { cache_prompts false }
      expect(klass.cache_prompts).to be false
    end

    it "inherits from parent" do
      parent = Class.new(RubyLLM::Agents::Base) { cache_prompts true }
      child = Class.new(parent)
      expect(child.cache_prompts).to be true
    end

    it "can be overridden by child" do
      parent = Class.new(RubyLLM::Agents::Base) { cache_prompts true }
      child = Class.new(parent) { cache_prompts false }
      expect(child.cache_prompts).to be false
    end

    it "appears in config_summary when enabled" do
      klass = Class.new(RubyLLM::Agents::Base) { cache_prompts true }
      expect(klass.config_summary[:cache_prompts]).to be true
    end

    it "is omitted from config_summary when disabled" do
      klass = Class.new(RubyLLM::Agents::Base) { cache_prompts false }
      # false is falsy, .compact removes nil but not false
      # Our implementation returns `cache_prompts || nil` which makes false → nil → compacted out
      expect(klass.config_summary).not_to have_key(:cache_prompts)
    end
  end

  describe "system prompt caching" do
    let(:claude_model_info) do
      info = double("ModelInfo")
      allow(info).to receive(:provider).and_return("anthropic")
      allow(info).to receive(:pricing).and_return(nil)
      info
    end

    it "marks the system prompt as a prompt cache boundary for Anthropic models" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "claude-sonnet-4-20250514"
        system "You are a helpful assistant."
        user "Hello"
        cache_prompts true
      end

      mock_client = build_mock_chat_client(response: build_mock_response(model_id: "claude-sonnet-4-20250514"))
      stub_ruby_llm_chat(mock_client)
      allow(RubyLLM::Models).to receive(:find).and_return(claude_model_info)

      expect(mock_client).to receive(:with_instructions)
        .with("You are a helpful assistant.", cache_until_here: true)
        .and_return(mock_client)

      klass.call
    end

    it "passes plain string for non-Anthropic models" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "gpt-4o"
        system "You are a helpful assistant."
        user "Hello"
        cache_prompts true
      end

      mock_client = build_mock_chat_client(response: build_mock_response)
      stub_ruby_llm_chat(mock_client)

      captured_content = nil
      allow(mock_client).to receive(:with_instructions) do |content|
        captured_content = content
        mock_client
      end

      # Model info returns OpenAI provider
      openai_info = double("ModelInfo", provider: "openai", pricing: nil)
      allow(RubyLLM::Models).to receive(:find).and_return(openai_info)

      klass.call

      expect(captured_content).to eq("You are a helpful assistant.")
    end

    it "passes plain string when cache_prompts is not enabled" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "claude-sonnet-4-20250514"
        system "You are a helpful assistant."
        user "Hello"
      end

      mock_client = build_mock_chat_client(response: build_mock_response(model_id: "claude-sonnet-4-20250514"))
      stub_ruby_llm_chat(mock_client)

      captured_content = nil
      allow(mock_client).to receive(:with_instructions) do |content|
        captured_content = content
        mock_client
      end

      klass.call

      expect(captured_content).to eq("You are a helpful assistant.")
    end
  end

  describe "tool definition caching" do
    let(:test_tool) do
      Class.new(RubyLLM::Tool) do
        def self.name = "test_tool"
        description "A test tool"
        parameter :input, type: :string, description: "Input text"
        def execute(input:) = "result"
      end
    end

    let(:another_tool) do
      Class.new(RubyLLM::Tool) do
        def self.name = "another_tool"
        description "Another test tool"
        parameter :query, type: :string, description: "Query text"
        def execute(query:) = "result"
      end
    end

    let(:claude_model_info) do
      info = double("ModelInfo")
      allow(info).to receive(:provider).and_return("anthropic")
      allow(info).to receive(:pricing).and_return(nil)
      info
    end

    it "adds cache_control to the last tool's provider_options" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "claude-sonnet-4-20250514"
        system "You are a helpful assistant."
        user "Hello"
        cache_prompts true
      end
      klass.tools(test_tool, another_tool)

      mock_client = build_mock_chat_client(response: build_mock_response(model_id: "claude-sonnet-4-20250514"))

      # Track tools hash to verify cache_control on last tool
      tools_hash = {}
      allow(mock_client).to receive(:with_tools) do |*tool_args|
        # Simulate RubyLLM::Chat#with_tools — instantiate and store
        tool_args.each do |t|
          instance = t.is_a?(Class) ? t.new : t
          tools_hash[instance.name.to_sym] = instance
        end
        mock_client
      end
      allow(mock_client).to receive(:tools).and_return(tools_hash)
      stub_ruby_llm_chat(mock_client)
      allow(RubyLLM::Models).to receive(:find).and_return(claude_model_info)

      klass.call

      last_tool = tools_hash.values.last
      expect(last_tool.provider_options).to include(cache_control: {type: "ephemeral"})

      # First tool should NOT have cache_control
      first_tool = tools_hash.values.first
      expect(first_tool.provider_options).not_to have_key(:cache_control)

      # The tool class itself is left untouched
      expect(another_tool.provider_options).not_to have_key(:cache_control)
    end

    it "does not modify tools when cache_prompts is disabled" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "claude-sonnet-4-20250514"
        system "You are a helpful assistant."
        user "Hello"
      end
      klass.tools(test_tool)

      mock_client = build_mock_chat_client(response: build_mock_response(model_id: "claude-sonnet-4-20250514"))

      tools_hash = {}
      allow(mock_client).to receive(:with_tools) do |*tool_args|
        tool_args.each do |t|
          instance = t.is_a?(Class) ? t.new : t
          tools_hash[instance.name.to_sym] = instance
        end
        mock_client
      end
      allow(mock_client).to receive(:tools).and_return(tools_hash)
      stub_ruby_llm_chat(mock_client)

      klass.call

      last_tool = tools_hash.values.last
      expect(last_tool.provider_options).not_to have_key(:cache_control)
    end
  end

  describe "rendered Anthropic request" do
    let(:llm) { RubyLLM.context { |config| config.anthropic_api_key = "test-key" } }
    let(:real_chat) { llm.chat(model: "claude-sonnet-4-20250514", provider: :anthropic, assume_model_exists: true) }

    let(:tool_classes) do
      %w[first_lookup second_lookup].map do |tool_name|
        Class.new(RubyLLM::Tool) do
          define_singleton_method(:name) { tool_name }
          description "Looks things up"
          parameter :query, description: "Query"
          def execute(query:) = "result"
        end
      end
    end

    def render_request_for(agent_class)
      allow(RubyLLM).to receive(:chat).and_return(real_chat)
      client = agent_class.new.send(:build_client)
      client.add_message(role: :user, content: "Hello")
      client.render
    end

    it "puts cache_control on the system prompt and the last tool" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "claude-sonnet-4-20250514"
        system "You are a helpful assistant."
        user "Hello"
        cache_prompts true
      end
      klass.tools(*tool_classes)

      payload = render_request_for(klass)

      expect(payload[:system].last).to include(text: "You are a helpful assistant.", cache_control: {type: "ephemeral"})
      expect(payload[:tools].last).to include(cache_control: {type: "ephemeral"})
      expect(payload[:tools].first).not_to have_key(:cache_control)
    end

    it "sends no cache_control when cache_prompts is off" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "claude-sonnet-4-20250514"
        system "You are a helpful assistant."
        user "Hello"
      end
      klass.tools(*tool_classes)

      payload = render_request_for(klass)

      expect(payload[:system].last).not_to have_key(:cache_control)
      expect(payload[:tools]).to all(satisfy { |tool| !tool.key?(:cache_control) })
    end
  end

  describe "cache token capture" do
    it "stores cached_tokens in context metadata" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "claude-sonnet-4-20250514"
        system "You are a helpful assistant."
        user "Hello"
        cache_prompts true
      end

      response = build_mock_response(
        model_id: "claude-sonnet-4-20250514",
        cached_tokens: 1500,
        cache_creation_tokens: 0
      )
      mock_client = build_mock_chat_client(response: response)
      stub_ruby_llm_chat(mock_client)

      claude_info = double("ModelInfo", provider: "anthropic")
      text_tokens = double("TextTokens", input: 3.0, output: 15.0)
      pricing = double("Pricing", text_tokens: text_tokens)
      allow(claude_info).to receive(:pricing).and_return(pricing)
      allow(RubyLLM::Models).to receive(:find).and_return(claude_info)

      result = klass.call
      # The Result carries the cache metrics through from the response — without
      # this they were captured onto the context and then silently dropped by
      # #build_result, landing as 0 in every persisted execution row.
      expect(result).to be_a(RubyLLM::Agents::Result)
      expect(result.cached_tokens).to eq(1500)
    end

    it "captures cache_creation_tokens when present" do
      klass = Class.new(RubyLLM::Agents::Base) do
        model "claude-sonnet-4-20250514"
        system "You are a helpful assistant."
        user "Hello"
        cache_prompts true
      end

      response = build_mock_response(
        model_id: "claude-sonnet-4-20250514",
        cached_tokens: 0,
        cache_creation_tokens: 2000
      )
      mock_client = build_mock_chat_client(response: response)
      stub_ruby_llm_chat(mock_client)

      claude_info = double("ModelInfo", provider: "anthropic")
      text_tokens = double("TextTokens", input: 3.0, output: 15.0)
      pricing = double("Pricing", text_tokens: text_tokens)
      allow(claude_info).to receive(:pricing).and_return(pricing)
      allow(RubyLLM::Models).to receive(:find).and_return(claude_info)

      result = klass.call
      expect(result).to be_a(RubyLLM::Agents::Result)
      expect(result.cache_creation_tokens).to eq(2000)
    end
  end

  describe "anthropic_model? detection" do
    let(:agent_instance) { RubyLLM::Agents::Base.new }

    it "detects Anthropic provider from model info" do
      info = double("ModelInfo", provider: "anthropic")
      allow(agent_instance).to receive(:find_model_info).and_return(info)

      expect(agent_instance.send(:anthropic_model?, "claude-sonnet-4-20250514")).to be true
    end

    it "rejects non-Anthropic provider" do
      info = double("ModelInfo", provider: "openai")
      allow(agent_instance).to receive(:find_model_info).and_return(info)

      expect(agent_instance.send(:anthropic_model?, "gpt-4o")).to be false
    end

    it "falls back to model ID pattern when registry unavailable" do
      allow(agent_instance).to receive(:find_model_info).and_return(nil)

      expect(agent_instance.send(:anthropic_model?, "claude-sonnet-4-20250514")).to be true
      expect(agent_instance.send(:anthropic_model?, "claude-3-haiku-20240307")).to be true
      expect(agent_instance.send(:anthropic_model?, "gpt-4o")).to be false
    end
  end
end
