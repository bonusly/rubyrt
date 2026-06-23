# frozen_string_literal: true

require 'ruby_llm'

module Rubyrt
  # Thin wrapper around ruby_llm for code review prompts.
  class LlmClient
    # Maps RubyRT provider names to the RubyLLM config attribute names.
    PROVIDER_CONFIG = {
      'openai' => { key: :openai_api_key, base: :openai_api_base },
      'anthropic' => { key: :anthropic_api_key, base: :anthropic_api_base },
      'gemini' => { key: :gemini_api_key, base: :gemini_api_base },
      'ollama' => { key: :ollama_api_key, base: :ollama_api_base },
      'deepseek' => { key: :deepseek_api_key, base: :deepseek_api_base },
      'openrouter' => { key: :openrouter_api_key, base: :openrouter_api_base },
      'mistral' => { key: :mistral_api_key, base: :mistral_api_base },
      'perplexity' => { key: :perplexity_api_key, base: :perplexity_api_base },
      'xai' => { key: :xai_api_key, base: :xai_api_base },
      'azure' => { key: :azure_api_key, base: :azure_api_base },
      'bedrock' => { key: :bedrock_api_key, base: :bedrock_api_base },
      'vertexai' => { key: :vertexai_service_account_key, base: :vertexai_api_base },
      'gpustack' => { key: :gpustack_api_key, base: :gpustack_api_base }
    }.freeze

    def initialize(config)
      @config = config
      validate!
      configure!
    end

    def complete(prompt)
      chat.ask(prompt)
    end

    private

    def validate!
      return if @config['llm_api_key'] && !@config['llm_api_key'].to_s.strip.empty?

      raise ConfigurationError,
            'Missing LLM_API_KEY. Set it as an environment variable or in ~/.rubyrt/.env.'
    end

    def configure!
      RubyLLM.configure do |ruby_llm_config|
        apply_provider_config(ruby_llm_config)
        ruby_llm_config.request_timeout = @config['request_timeout'] if @config['request_timeout']
        ruby_llm_config.max_retries = @config['retries'] if @config['retries']
        apply_logging_config(ruby_llm_config)
      end
    end

    def apply_logging_config(ruby_llm_config)
      log_file = @config['log_file']
      ruby_llm_config.log_file = log_file if log_file && !log_file.to_s.strip.empty?

      level = parse_log_level(@config['log_level'])
      ruby_llm_config.log_level = level if level
    end

    def parse_log_level(value)
      return nil unless value && !value.to_s.strip.empty?

      Logger::SEV_LABEL.index(value.to_s.upcase) || Logger::INFO
    end

    def chat
      RubyLLM.chat(model: @config['model'], provider: @config['provider'])
    end

    def apply_provider_config(config)
      provider = @config['provider'].to_s
      mapping = PROVIDER_CONFIG[provider]
      raise ArgumentError, "Unsupported LLM provider: #{provider}" unless mapping

      config.public_send("#{mapping[:key]}=", @config['llm_api_key'])
      config.public_send("#{mapping[:base]}=", @config['llm_api_base']) if @config['llm_api_base']
    end
  end
end
