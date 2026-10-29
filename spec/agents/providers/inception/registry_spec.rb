# frozen_string_literal: true

require "rails_helper"

RSpec.describe RubyLLM::Agents::Providers::Inception::Registry do
  describe "catalog registration" do
    it "registers the catalog file with RubyLLM" do
      expect(RubyLLM::Provider.model_registry_files[:inception]).to eq(described_class::FILE)
    end

    it "resolves all Mercury models through the RubyLLM registry" do
      registry = RubyLLM::Models.new
      described_class::MODELS.each do |model_id|
        model = registry.find(model_id)
        expect(model).to be_a(RubyLLM::Model)
        expect(model.id).to eq(model_id)
        expect(model.provider).to eq("inception")
      end
    end

    it "ships a catalog file in sync with Capabilities" do
      shipped = JSON.parse(File.read(described_class::FILE))
      expect(shipped).to eq(JSON.parse(JSON.generate(described_class.catalog)))
    end
  end

  describe ".write!" do
    it "writes the catalog as a RubyLLM registry file" do
      Tempfile.create(["inception", ".json"]) do |file|
        described_class.write!(file.path)
        models = RubyLLM::Models.new(RubyLLM::Models.models_from_file(file.path))
        expect(models.all.map(&:id)).to eq(described_class::MODELS)
      end
    end
  end

  let(:registry) { RubyLLM::Models.new }

  describe "mercury-2 model resolution" do
    let(:model) { registry.find("mercury-2") }

    it "has correct provider" do
      expect(model.provider).to eq("inception")
    end

    it "has correct name" do
      expect(model.name).to eq("Mercury 2")
    end

    it "has correct family" do
      expect(model.family).to eq("mercury")
    end

    it "has 128K context window" do
      expect(model.context_window).to eq(128_000)
    end

    it "has 32K max output tokens" do
      expect(model.max_output_tokens).to eq(32_000)
    end

    it "supports streaming" do
      expect(model.capabilities).to include("streaming")
    end

    it "supports function calling" do
      expect(model.capabilities).to include("function_calling")
    end

    it "supports structured output" do
      expect(model.capabilities).to include("structured_output")
    end

    it "supports reasoning" do
      expect(model.capabilities).to include("reasoning")
    end

    it "has text-only modalities" do
      expect(model.modalities.input).to eq(["text"])
      expect(model.modalities.output).to eq(["text"])
    end

    it "has correct pricing" do
      expect(model.pricing.text_tokens.standard.input_per_million).to eq(0.25)
      expect(model.pricing.text_tokens.standard.output_per_million).to eq(0.75)
    end
  end

  describe "mercury model resolution" do
    let(:model) { registry.find("mercury") }

    it "resolves to inception provider" do
      expect(model.provider).to eq("inception")
    end

    it "does not include reasoning" do
      expect(model.capabilities).not_to include("reasoning")
    end
  end

  describe "mercury-coder-small model resolution" do
    let(:model) { registry.find("mercury-coder-small") }

    it "resolves to inception provider" do
      expect(model.provider).to eq("inception")
    end

    it "has only streaming capability" do
      expect(model.capabilities).to eq(["streaming"])
    end

    it "has higher output pricing" do
      expect(model.pricing.text_tokens.standard.output_per_million).to eq(1.00)
    end
  end

  describe "mercury-edit model resolution" do
    let(:model) { registry.find("mercury-edit") }

    it "resolves to inception provider" do
      expect(model.provider).to eq("inception")
    end

    it "has only streaming capability" do
      expect(model.capabilities).to eq(["streaming"])
    end
  end
end
