# frozen_string_literal: true

require 'logger'
require 'ruby_llm'
require_relative 'errors'

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

    LOG_LEVELS = {
      'debug' => Logger::DEBUG, 'info' => Logger::INFO, 'warn' => Logger::WARN,
      'error' => Logger::ERROR, 'fatal' => Logger::FATAL
    }.freeze

    def initialize(config)
      @config = config
      validate!
      @llm_context = build_context
    end

    # Per-instance RubyLLM context; configuration never mutates global state, so
    # multiple clients with different providers/keys can coexist safely.
    attr_reader :llm_context

    def complete(prompt)
      chat.ask(prompt)
    end

    def complete_with_schema(prompt, schema)
      chat.with_schema(schema).ask(prompt)
    end

    private

    def validate!
      return if @config['llm_api_key'] && !@config['llm_api_key'].to_s.strip.empty?

      raise ConfigurationError,
            'Missing LLM_API_KEY. Set it as an environment variable or in ~/.rubyrt/.env.'
    end

    def build_context
      RubyLLM.context do |llm_config|
        apply_provider_config(llm_config)
        llm_config.request_timeout = @config['request_timeout'] if @config['request_timeout']
        llm_config.max_retries = @config['retries'] if @config['retries']
        apply_logging_config(llm_config)
      end
    end

    def apply_logging_config(llm_config)
      log_file = @config['log_file']
      llm_config.log_file = log_file if log_file && !log_file.to_s.strip.empty?

      level = parse_log_level(@config['log_level'])
      llm_config.log_level = level if level
    end

    def parse_log_level(value)
      return nil unless value && !value.to_s.strip.empty?

      LOG_LEVELS.fetch(value.to_s.downcase, Logger::INFO)
    end

    def chat
      llm_context.chat(model: @config['model'], provider: @config['provider'])
    end

    def apply_provider_config(llm_config)
      provider = @config['provider'].to_s
      mapping = PROVIDER_CONFIG[provider]
      raise ArgumentError, "Unsupported LLM provider: #{provider}" unless mapping

      llm_config.public_send("#{mapping[:key]}=", @config['llm_api_key'])
      llm_config.public_send("#{mapping[:base]}=", @config['llm_api_base']) if @config['llm_api_base']
    end
  end
end
