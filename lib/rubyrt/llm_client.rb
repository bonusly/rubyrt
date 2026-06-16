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
        ruby_llm_config.openai_api_key = @config['llm_api_key']
        ruby_llm_config.openai_api_base = @config['llm_api_base'] if @config['llm_api_base']
      end
    end

    def chat
      RubyLLM.chat(model: @config['model'])
    end
  end
end
