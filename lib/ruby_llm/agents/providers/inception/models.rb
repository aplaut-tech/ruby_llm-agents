# frozen_string_literal: true

module RubyLLM
  module Agents
    module Providers
      class Inception < ::RubyLLM::Provider
        # Parses model metadata from the Inception /models API endpoint.
        # Response format is OpenAI-compatible; context window, pricing and
        # capabilities come from Capabilities because the API omits them.
        module Models
          module_function

          def parse_list_models_response(response, slug)
            Array(response.body["data"]).map do |model_data|
              model_id = model_data["id"]

              ::RubyLLM::Model.new(
                **Registry.model_attributes(model_id),
                provider: slug,
                created_at: model_data["created"] ? Time.at(model_data["created"]) : nil,
                metadata: {
                  object: model_data["object"],
                  owned_by: model_data["owned_by"]
                }.compact
              )
            end
          end
        end
      end
    end
  end
end
