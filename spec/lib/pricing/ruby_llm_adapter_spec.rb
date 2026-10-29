# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Pricing::RubyLLMAdapter do
  describe ".find_model" do
    context "with a known text LLM model" do
      # Both models ship in the registry bundled with ruby_llm.
      it "returns pricing for gpt-4o" do
        result = described_class.find_model("gpt-4o")

        expect(result[:input_cost_per_token]).to be > 0
        expect(result[:output_cost_per_token]).to be > 0
        expect(result[:source]).to eq(:ruby_llm)
        expect(result[:mode]).to eq("chat")
      end

      it "returns pricing for claude-sonnet-4-5" do
        result = described_class.find_model("claude-sonnet-4-5")

        expect(result[:input_cost_per_token]).to be > 0
        expect(result[:source]).to eq(:ruby_llm)
      end
    end

    context "with an unknown model" do
      it "returns nil" do
        result = described_class.find_model("totally-fake-model-xyz-999")
        expect(result).to be_nil
      end
    end

    context "with a whisper model" do
      it "attempts to find pricing" do
        result = described_class.find_model("whisper-1")
        # May or may not be in ruby_llm's registry
        if result
          expect(result[:source]).to eq(:ruby_llm)
        else
          expect(result).to be_nil
        end
      end
    end
  end
end
