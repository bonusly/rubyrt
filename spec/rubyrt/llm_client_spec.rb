# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Rubyrt::LlmClient do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:config_without_key) do
    Rubyrt::Configuration.new(
      root: tmp_dir,
      overrides: { 'llm_api_key' => nil, 'provider' => 'openai' }
    )
  end
  let(:config_with_key) do
    Rubyrt::Configuration.new(root: tmp_dir, overrides: { 'llm_api_key' => 'sk-test' })
  end

  let(:config) do
    Rubyrt::Configuration.new(
      root: tmp_dir,
      overrides: {
        provider: provider,
        llm_api_key: 'secret',
        llm_api_base: 'https://example.com/v1'
      }
    )
  end

  after do
    FileUtils.remove_entry(tmp_dir)
  end

  it 'raises when LLM_API_KEY is missing' do
    expect { described_class.new(config_without_key) }
      .to raise_error(Rubyrt::ConfigurationError, /Missing LLM_API_KEY/)
  end

  it 'constructs when LLM_API_KEY is present' do
    expect { described_class.new(config_with_key) }.not_to raise_error
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
