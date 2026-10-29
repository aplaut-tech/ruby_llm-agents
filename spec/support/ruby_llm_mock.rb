# frozen_string_literal: true

# Mock RubyLLM module for testing agents without actual API calls
module RubyLLM
  # Shaped like a RubyLLM 2 Message: usage in #tokens, model id in #model
  class MockResponse
    attr_reader :content, :tokens, :model

    def initialize(content, input_tokens: 10, output_tokens: 5, model_id: "gpt-4o")
      @content = content
      @tokens = RubyLLM::Tokens.new(input: input_tokens, output: output_tokens)
      @model = model_id
    end

    def role
      :assistant
    end

    # Thinking support (returns nil by default)
    def thinking
      nil
    end

    def thinking_content
      nil
    end

    def tool_call?
      false
    end

    def tool_calls
      []
    end

    # Finish reason (:stop, :max_tokens, :tool_calls, etc.)
    def finish_reason
      :stop
    end
  end

  class MockClient
    attr_reader :model, :temperature, :instructions, :schema, :tools, :messages

    def initialize
      @model = nil
      @temperature = nil
      @instructions = nil
      @schema = nil
      @messages = []
      @tools = []
    end

    def with_model(model)
      @model = model
      self
    end

    def with_temperature(temperature)
      @temperature = temperature
      self
    end

    def with_instructions(instructions)
      @instructions = instructions
      self
    end

    def with_schema(schema)
      @schema = schema
      self
    end

    def with_tools(*tools)
      @tools = tools
      self
    end

    def with_tool_options(**options)
      @tool_options = options
      self
    end

    def with_thinking(**options)
      @thinking_options = options
      self
    end

    def before_tool_call(&block)
      @before_tool_call = block
      self
    end

    def after_tool_result(&block)
      @after_tool_result = block
      self
    end

    def add_message(role:, content:)
      @messages << {role: role, content: content}
      self
    end

    def ask(_prompt, **_opts)
      MockResponse.new("Mock response")
    end

    def generate
      MockResponse.new("Mock response")
    end

    def complete
      MockResponse.new("Mock response")
    end
  end

  # Mock embedding response, shaped like RubyLLM 2's Embedding
  class MockEmbeddingResponse
    attr_reader :vectors, :model, :tokens

    def initialize(vectors: nil, model_id: "text-embedding-3-small", input_tokens: 10, dimensions: 1536)
      @vectors = vectors || [Array.new(dimensions) { rand(-1.0..1.0) }]
      @model = model_id
      @tokens = RubyLLM::Tokens.new(input: input_tokens)
    end

    def embedding
      @vectors.first
    end

    def embeddings
      @vectors
    end
  end

  # Mock moderation response
  class MockModerationResponse
    attr_reader :model_id, :results

    def initialize(flagged: false, model_id: "omni-moderation-latest", categories: {})
      @model_id = model_id
      @flagged = flagged
      @categories = categories
      @results = [{flagged: flagged, categories: categories, category_scores: {}}]
    end

    def flagged?
      @flagged
    end

    attr_reader :categories

    def category_scores
      {}
    end
  end

  # Mock transcription response
  class MockTranscriptionResponse
    attr_reader :text, :model_id, :language, :duration, :segments

    def initialize(text: "Mock transcription", model_id: "whisper-1", language: "en", duration: 10.0)
      @text = text
      @model_id = model_id
      @language = language
      @duration = duration
      @segments = []
    end

    def cost
      0.006
    end
  end

  # Mock image generation response
  class MockImageResponse
    attr_reader :url, :data, :model_id, :revised_prompt

    def initialize(url: "https://example.com/image.png", data: nil, model_id: "dall-e-3", revised_prompt: nil)
      @url = url
      @data = data
      @model_id = model_id
      @revised_prompt = revised_prompt
    end

    def images
      [self]
    end

    def cost
      0.04
    end
  end

  class << self
    def chat(model: nil)
      client = MockClient.new
      client.with_model(model) if model
      client
    end

    # Embeddings
    def embed(input, model: nil, dimensions: nil, **options)
      MockEmbeddingResponse.new(model_id: model || "text-embedding-3-small", dimensions: dimensions || 1536)
    end

    # Moderation
    def moderate(input, model: nil, **options)
      MockModerationResponse.new(model_id: model || "omni-moderation-latest")
    end

    # Transcription
    def transcribe(audio, model: nil, **options)
      MockTranscriptionResponse.new(model_id: model || "whisper-1")
    end

    # Image generation
    def paint(prompt, model: nil, **options)
      MockImageResponse.new(model_id: model || "dall-e-3")
    end
  end
end
