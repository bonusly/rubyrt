# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Rubyrt::LlmClient do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:config_without_key) { Rubyrt::Configuration.new(root: tmp_dir) }
  let(:config_with_key) do
    Rubyrt::Configuration.new(root: tmp_dir, overrides: { 'llm_api_key' => 'sk-test' })
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
end
