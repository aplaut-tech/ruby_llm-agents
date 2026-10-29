# frozen_string_literal: true

module RubyLLM
  module Agents
    module Providers
      # Inception Labs Mercury API integration (OpenAI-compatible Chat Completions).
      # Mercury models are diffusion LLMs (dLLMs) that generate tokens
      # in parallel for dramatically faster inference.
      #
      # Registered as the +:inception+ provider together with its own model
      # catalog (see Registry), so RubyLLM resolves Mercury models without
      # calling the Inception /models API.
      #
      # @example
      #   RubyLLM.configure { |c| c.inception_api_key = ENV["INCEPTION_API_KEY"] }
      #   RubyLLM.chat(model: "mercury-2").ask("Hello")
      #
      # @see https://docs.inceptionlabs.ai/
      class Inception < ::RubyLLM::Provider
        def api_base
          @config.inception_api_base || "https://api.inceptionlabs.ai/v1"
        end

        def headers
          {
            "Authorization" => "Bearer #{@config.inception_api_key}"
          }
        end

        class << self
          def capabilities
            Inception::Capabilities
          end

          def configuration_options
            %i[inception_api_key inception_api_base]
          end

          def configuration_requirements
            %i[inception_api_key]
          end
        end
      end
    end
  end
end

require_relative "inception/capabilities"
require_relative "inception/models"
require_relative "inception/registry"

module RubyLLM
  module Agents
    module Providers
      class Inception < ::RubyLLM::Provider
        # Inception's dialect of the Chat Completions API: the standard wire
        # format, with the /models listing enriched from Capabilities.
        class ChatCompletions < ::RubyLLM::Protocols::ChatCompletions
          include Inception::Models
        end

        protocol :chat_completions, ChatCompletions
      end
    end
  end
end
