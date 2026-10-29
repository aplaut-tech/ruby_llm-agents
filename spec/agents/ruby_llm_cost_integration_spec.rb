# frozen_string_literal: true

require "rails_helper"

# End-to-end verification that a real agent run through the full pipeline
# persists a cache-aware total cost priced with RubyLLM::Cost, tying
# together capture_response -> calculate_costs -> instrumentation persistence.
RSpec.describe "RubyLLM cost integration", type: :model do
  let(:model_id) { "claude-haiku-4-5" } # has cache_read/cache_write pricing
  let(:pricing) { RubyLLM::Models.find(model_id).pricing.text_tokens }

  let(:agent_class) do
    Class.new(RubyLLM::Agents::Base) do
      def self.name
        "CacheCostAgent"
      end

      model "claude-haiku-4-5"
      param :query, required: true

      def user_prompt
        query
      end
    end
  end

  let(:response) do
    RubyLLM::Message.new(
      role: :assistant,
      content: "answer",
      model: model_id,
      input_tokens: 1000,
      output_tokens: 500,
      cache_read_tokens: 2000,
      cache_write_tokens: 100
    )
  end

  before do
    stub_agent_configuration(track_executions: true, async_logging: false)
    stub_ruby_llm_chat(build_mock_chat_client(response: response))
  end

  it "persists a total cost that includes cache read/write pricing" do
    result = agent_class.call(query: "hi")
    expect(result.content).to eq("answer")

    execution = RubyLLM::Agents::Execution.where(agent_type: "CacheCostAgent").last
    expect(execution).to be_present

    text_only = ((1000 / 1_000_000.0) * pricing.input) + ((500 / 1_000_000.0) * pricing.output)
    cache_extra = ((2000 / 1_000_000.0) * pricing.cache_read_input) +
      ((100 / 1_000_000.0) * pricing.cache_write_input)

    expect(execution.total_cost).to be_within(1e-9).of((text_only + cache_extra).round(6))
    expect(execution.total_cost).to be > text_only.round(6)
  end

  it "records the cache cost breakdown in execution metadata" do
    agent_class.call(query: "hi")

    execution = RubyLLM::Agents::Execution.where(agent_type: "CacheCostAgent").last
    breakdown = execution.metadata["cost_breakdown"]

    expect(breakdown).to be_present
    cache_extra = ((2000 / 1_000_000.0) * pricing.cache_read_input) +
      ((100 / 1_000_000.0) * pricing.cache_write_input)
    expect(breakdown.values.sum).to be_within(1e-9).of(cache_extra.round(6))
  end
end
