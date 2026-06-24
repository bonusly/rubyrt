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
    # RubyLLM is a global singleton; reset its config and logger so per-example
    # provider, key, timeout, retry, and logging settings don't leak.
    RubyLLM.instance_variable_set(:@config, nil)
    RubyLLM.instance_variable_set(:@logger, nil)
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

  context 'with timeout and retries from config' do
    let(:provider) { 'openai' }
    let(:config) do
      Rubyrt::Configuration.new(
        root: tmp_dir,
        overrides: {
          provider: provider,
          llm_api_key: 'secret',
          model: 'gpt-4o-mini',
          request_timeout: 45,
          retries: 7
        }
      )
    end

    it 'applies request_timeout and retries to RubyLLM', :aggregate_failures do
      described_class.new(config)
      expect(RubyLLM.config.request_timeout).to eq(45)
      expect(RubyLLM.config.max_retries).to eq(7)
    end

    it 'passes the configured provider and model to RubyLLM.chat so requests route correctly' do
      client = described_class.new(config)
      chat_double = instance_double(RubyLLM::Chat, ask: 'response')
      allow(RubyLLM).to receive(:chat).and_return(chat_double)
      client.complete('test prompt')
      expect(RubyLLM).to have_received(:chat).with(model: 'gpt-4o-mini', provider: 'openai')
    end
  end

  context 'with log_file and log_level from config' do
    let(:provider) { 'openai' }
    let(:config) do
      Rubyrt::Configuration.new(
        root: tmp_dir,
        overrides: {
          provider: provider,
          llm_api_key: 'secret',
          log_file: File.join(tmp_dir, 'rubyrt-test.log'),
          log_level: 'debug'
        }
      )
    end

    it 'applies log_file and log_level to RubyLLM', :aggregate_failures do
      described_class.new(config)
      expect(RubyLLM.config.log_file).to eq(File.join(tmp_dir, 'rubyrt-test.log'))
      expect(RubyLLM.config.log_level).to eq(Logger::DEBUG)
    end
  end

  context 'with an invalid log_level' do
    let(:provider) { 'openai' }
    let(:config) do
      Rubyrt::Configuration.new(
        root: tmp_dir,
        overrides: {
          provider: provider,
          llm_api_key: 'secret',
          log_level: 'verbose'
        }
      )
    end

    it 'falls back to info level' do
      described_class.new(config)
      expect(RubyLLM.config.log_level).to eq(Logger::INFO)
    end
  end
end
