# frozen_string_literal: true

require 'ruby_llm'

module Rubyrt
  # Thin wrapper around ruby_llm for code review prompts.
  class LlmClient
    def initialize(config)
      @config = config
      configure!
    end

    def complete(prompt)
      chat.ask(prompt)
    end

    private

    def configure!
      RubyLLM.configure do |ruby_llm_config|
        apply_provider_config(ruby_llm_config)
      end
    end

    def chat
      RubyLLM.chat(model: @config['model'])
    end

    def apply_provider_config(config)
      provider = @config['provider'].to_s
      api_key = @config['llm_api_key']
      api_base = @config['llm_api_base']

      case provider
      when 'openai'
        config.openai_api_key = api_key
        config.openai_api_base = api_base if api_base
      when 'anthropic'
        config.anthropic_api_key = api_key
        config.anthropic_api_base = api_base if api_base
      when 'gemini'
        config.gemini_api_key = api_key
        config.gemini_api_base = api_base if api_base
      when 'ollama'
        config.ollama_api_key = api_key if api_key
        config.ollama_api_base = api_base if api_base
      when 'deepseek'
        config.deepseek_api_key = api_key
        config.deepseek_api_base = api_base if api_base
      when 'openrouter'
        config.openrouter_api_key = api_key
        config.openrouter_api_base = api_base if api_base
      when 'mistral'
        config.mistral_api_key = api_key
        config.mistral_api_base = api_base if api_base
      when 'perplexity'
        config.perplexity_api_key = api_key
        config.perplexity_api_base = api_base if api_base
      when 'xai'
        config.xai_api_key = api_key
        config.xai_api_base = api_base if api_base
      when 'azure'
        config.azure_api_key = api_key
        config.azure_api_base = api_base if api_base
      when 'bedrock'
        config.bedrock_api_key = api_key
        config.bedrock_api_base = api_base if api_base
      when 'vertexai'
        config.vertexai_service_account_key = api_key
        config.vertexai_api_base = api_base if api_base
      when 'gpustack'
        config.gpustack_api_key = api_key
        config.gpustack_api_base = api_base if api_base
      else
        raise ArgumentError, "Unsupported LLM provider: #{provider}"
      end
    end
  end
end
