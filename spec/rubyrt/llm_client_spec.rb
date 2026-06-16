# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rubyrt::LlmClient do
  let(:config) do
    Rubyrt::Configuration.new(
      root: Dir.mktmpdir,
      overrides: {
        provider: provider,
        llm_api_key: 'secret',
        llm_api_base: 'https://example.com/v1'
      }
    )
  end

  after do
    FileUtils.remove_entry(config.instance_variable_get(:@root)) if Dir.exist?(config.instance_variable_get(:@root))
  end

  context 'with an unsupported provider' do
    let(:provider) { 'unknown' }

    it 'raises an argument error' do
      expect { described_class.new(config) }.to raise_error(ArgumentError, /Unsupported LLM provider/)
    end
  end

  context 'with openai' do
    let(:provider) { 'openai' }

    it 'configures the openai provider' do
      client = described_class.new(config)
      expect(RubyLLM.config.openai_api_key).to eq('secret')
      expect(RubyLLM.config.openai_api_base).to eq('https://example.com/v1')
      expect(client).to be_a(described_class)
    end
  end

  context 'with anthropic' do
    let(:provider) { 'anthropic' }

    it 'configures the anthropic provider' do
      described_class.new(config)
      expect(RubyLLM.config.anthropic_api_key).to eq('secret')
      expect(RubyLLM.config.anthropic_api_base).to eq('https://example.com/v1')
    end
  end
end
