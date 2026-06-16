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
    FileUtils.rm_rf(config.instance_variable_get(:@root))
  end

  context 'with an unsupported provider' do
    let(:provider) { 'unknown' }

    it 'raises an argument error' do
      expect { described_class.new(config) }.to raise_error(ArgumentError, /Unsupported LLM provider/)
    end
  end

  context 'with openai' do
    let(:provider) { 'openai' }

    it 'returns an llm client' do
      expect(described_class.new(config)).to be_a(described_class)
    end

    it 'configures the openai api key' do
      described_class.new(config)
      expect(RubyLLM.config.openai_api_key).to eq('secret')
    end

    it 'configures the openai api base' do
      described_class.new(config)
      expect(RubyLLM.config.openai_api_base).to eq('https://example.com/v1')
    end
  end

  context 'with anthropic' do
    let(:provider) { 'anthropic' }

    it 'configures the anthropic api key' do
      described_class.new(config)
      expect(RubyLLM.config.anthropic_api_key).to eq('secret')
    end

    it 'configures the anthropic api base' do
      described_class.new(config)
      expect(RubyLLM.config.anthropic_api_base).to eq('https://example.com/v1')
    end
  end
end
