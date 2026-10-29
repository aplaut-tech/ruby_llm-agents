# frozen_string_literal: true

require "rails_helper"

# Runs agents against a real RubyLLM::Chat (only the provider request is
# stubbed), so the request the agent configures and the response it reads
# are RubyLLM 2's own, not test doubles.
RSpec.describe "Agents on a real RubyLLM::Chat" do
  let(:llm) { RubyLLM.context { |config| config.openai_api_key = "test-key" } }
  let(:chat) { llm.chat(model: "gpt-4o-mini", provider: :openai, assume_model_exists: true) }

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

  let(:agent_class) do
    tool = lookup_tool
    Class.new(RubyLLM::Agents::Base) do
      def self.name
        "StructuredChatAgent"
      end

      model "gpt-4o-mini"
      temperature 0.2
      thinking effort: :low
      system "Summarize the request."
      user "{question}"
      tools tool
      tool_concurrency false

      returns do
        string :summary, description: "One sentence"
        integer :score
      end
    end
  end

  def answer(content, finish_reason: :stop)
    RubyLLM::Message.new(
      role: :assistant, content: content, model: "gpt-4o-mini-2024-07-18",
      input_tokens: 120, output_tokens: 30, finish_reason: finish_reason
    )
  end

  before do
    stub_agent_configuration(track_executions: true, async_logging: false)
    allow(RubyLLM).to receive(:chat).and_return(chat)
  end

  describe "the rendered request" do
    let(:payload) do
      client = agent_class.new(question: "hi").send(:build_client)
      client.add_message(role: :user, content: "hi")
      client.render
    end

    it "asks for the schema as structured output" do
      format = payload.dig(:text, :format)

      expect(format).to include(type: "json_schema")
      expect(format[:schema][:properties].keys).to contain_exactly(:summary, :score)
    end

    it "sends the system prompt, temperature, effort and tools" do
      expect(payload[:instructions]).to eq("Summarize the request.")
      expect(payload[:temperature]).to eq(0.2)
      expect(payload[:reasoning]).to eq(effort: "low")
      expect(payload[:tools].map { |tool| tool[:name] }).to eq([lookup_tool.new.name])
    end

    it "runs tools sequentially when the agent says so" do
      client = agent_class.new(question: "hi").send(:build_client)

      expect(client.tool_options[:concurrency]).to be_nil
    end
  end

  describe "the result" do
    it "returns the structured output as a symbolized hash" do
      allow_any_instance_of(RubyLLM::Providers::OpenAI).to receive(:complete)
        .and_return(answer({summary: "All good", score: 7}.to_json))

      result = agent_class.call(question: "How was it?")

      expect(result.content).to eq(summary: "All good", score: 7)
      expect(result.input_tokens).to eq(120)
      expect(result.output_tokens).to eq(30)
      expect(result.chosen_model_id).to eq("gpt-4o-mini-2024-07-18")
      expect(result.finish_reason).to eq("stop")
    end

    it "reports a response cut off by the token limit as truncated" do
      allow_any_instance_of(RubyLLM::Providers::OpenAI).to receive(:complete)
        .and_return(answer('{"summary": "All', finish_reason: :max_tokens))

      result = agent_class.call(question: "How was it?")

      expect(result.finish_reason).to eq("length")
      expect(result).to be_truncated
      expect(result.content).to eq('{"summary": "All')

      execution = RubyLLM::Agents::Execution.last
      expect(execution.status).to eq("success")
      expect(execution.finish_reason).to eq("length")
    end
  end
end
