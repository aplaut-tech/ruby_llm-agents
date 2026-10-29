# frozen_string_literal: true

require "json"

module RubyLLM
  module Agents
    module Providers
      class Inception < ::RubyLLM::Provider
        # The Mercury model catalog shipped with the gem.
        #
        # RubyLLM 2 loads a provider gem's models from the JSON registry file
        # passed to RubyLLM::Provider.register (see FILE). The file is
        # generated from Capabilities, so the two never drift:
        #
        #   RubyLLM::Agents::Providers::Inception::Registry.write!
        module Registry
          MODELS = %w[mercury-2 mercury mercury-coder-small mercury-edit].freeze

          FILE = File.expand_path("models.json", __dir__)

          module_function

          # @param model_id [String]
          # @return [Hash] Registry attributes of a Mercury model
          def model_attributes(model_id)
            {
              id: model_id,
              name: Capabilities.format_display_name(model_id),
              provider: "inception",
              family: Capabilities.model_family(model_id).to_s,
              context_window: Capabilities.context_window_for(model_id),
              max_output_tokens: Capabilities.max_tokens_for(model_id),
              modalities: Capabilities.modalities_for(model_id),
              capabilities: Capabilities.capabilities_for(model_id),
              pricing: Capabilities.pricing_for(model_id)
            }
          end

          # @return [Array<Hash>] The catalog in RubyLLM's registry file shape
          def catalog
            MODELS.map { |model_id| ::RubyLLM::Model.new(model_attributes(model_id)).to_h }
          end

          # Regenerates the JSON registry file from Capabilities.
          #
          # @param path [String] Destination file
          # @return [String] The path written
          def write!(path = FILE)
            File.write(path, "#{JSON.pretty_generate(catalog)}\n")
            path
          end
        end
      end
    end
  end
end
