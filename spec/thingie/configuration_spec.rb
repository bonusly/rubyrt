# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Thingie::Configuration do
  subject(:config) { described_class.new(root: tmp_dir) }

  let(:tmp_dir) { Dir.mktmpdir }

  # Clean up the temp dir so the suite doesn't leak directories, and keep it
  # hermetic by never reading a developer's real ~/.rubyrt/.env.
  before { stub_const('Thingie::Configuration::USER_ENV_FILE', File.join(tmp_dir, 'no-such.env')) }
  after { FileUtils.rm_rf(tmp_dir) }

  it 'loads bundled defaults', :aggregate_failures do
    expect(config['retries']).to eq(3)
    expect(config['request_timeout']).to eq(120)
    expect(config['models_file']).to eq('')
  end

  it 'exposes prompt_vars' do
    expect(config.prompt_vars).to include('self_id', 'requirements', 'json_requirements')
  end

  context 'with a project config file' do
    before do
      FileUtils.mkdir_p(File.join(tmp_dir, '.rubyrt'))
      File.write(File.join(tmp_dir, '.rubyrt', 'config.toml'), <<~TOML)
        retries = 10
        model = "claude-sonnet-4"

        [prompt_vars]
        requirements = "Extra requirement."
      TOML
    end

    it 'overrides simple keys', :aggregate_failures do
      expect(config['retries']).to eq(10)
      expect(config['model']).to eq('claude-sonnet-4')
    end

    it 'deep-merges prompt_vars', :aggregate_failures do
      expect(config.prompt_vars['requirements']).to eq('Extra requirement.')
      expect(config.prompt_vars['self_id']).to include('AI-powered')
    end
  end

  context 'with ~/.rubyrt/.env' do
    let(:env_file) { File.join(tmp_dir, 'fake-home.env') }

    around do |example|
      original = ENV.fetch('LLM_API_KEY', nil)
      ENV.delete('LLM_API_KEY')
      example.run
    ensure
      original ? ENV['LLM_API_KEY'] = original : ENV.delete('LLM_API_KEY')
    end

    before do
      File.write(env_file, "LLM_API_KEY=from-dotenv-file\n")
      stub_const('Thingie::Configuration::USER_ENV_FILE', env_file)
    end

    it 'loads LLM_API_KEY from the env file' do
      expect(config['llm_api_key']).to eq('from-dotenv-file')
    end
  end

  context 'with environment variables' do
    around do |example|
      original = ENV.fetch('LLM_MODEL', nil)
      ENV['LLM_MODEL'] = 'gpt-5'
      example.run
    ensure
      original ? ENV['LLM_MODEL'] = original : ENV.delete('LLM_MODEL')
    end

    it 'overrides model from environment' do
      expect(config['model']).to eq('gpt-5')
    end
  end

  context 'with RUBYRT_MODELS_FILE environment variable' do
    around do |example|
      original = ENV.fetch('RUBYRT_MODELS_FILE', nil)
      ENV['RUBYRT_MODELS_FILE'] = '/tmp/rubyrt-models.json'
      example.run
    ensure
      original ? ENV['RUBYRT_MODELS_FILE'] = original : ENV.delete('RUBYRT_MODELS_FILE')
    end

    it 'overrides models_file from environment' do
      expect(config['models_file']).to eq('/tmp/rubyrt-models.json')
    end
  end

  context 'with explicit overrides' do
    subject(:config) { described_class.new(root: tmp_dir, overrides: { model: 'o1-preview' }) }

    it 'overrides model from constructor options' do
      expect(config['model']).to eq('o1-preview')
    end
  end

  context 'with environment variable and explicit override' do
    subject(:config) { described_class.new(root: tmp_dir, overrides: { model: 'o1-preview' }) }

    around do |example|
      original = ENV.fetch('LLM_MODEL', nil)
      ENV['LLM_MODEL'] = 'gpt-5'
      example.run
    ensure
      original ? ENV['LLM_MODEL'] = original : ENV.delete('LLM_MODEL')
    end

    it 'prefers explicit override over environment variable' do
      expect(config['model']).to eq('o1-preview')
    end
  end

  context 'with skill directories' do
    before do
      %w[.agents .claude .cursor].each do |source|
        FileUtils.mkdir_p(File.join(tmp_dir, source))
        File.write(File.join(tmp_dir, source, 'rails_rules.md'), "#{source} rule")
      end
    end

    it 'discovers markdown skill files', :aggregate_failures do
      expect(config.skills.size).to eq(3)
      expect(config.skills.map(&:name)).to contain_exactly('rails_rules', 'rails_rules', 'rails_rules')
    end

    it 'captures content and source', :aggregate_failures do
      skill = config.skills.find { |s| s.source.end_with?('.agents') }
      expect(skill.source).to end_with('.agents')
      expect(skill.content).to eq('.agents rule')
    end
  end

  context 'with custom skill_directories' do
    subject(:config) do
      described_class.new(root: tmp_dir, overrides: { skill_directories: ['.github'] })
    end

    before do
      FileUtils.mkdir_p(File.join(tmp_dir, '.github'))
      File.write(File.join(tmp_dir, '.github', 'review_rules.md'), 'Custom rules.')
      # Create a default skill dir that should NOT be loaded
      FileUtils.mkdir_p(File.join(tmp_dir, '.agents'))
      File.write(File.join(tmp_dir, '.agents', 'default_rules.md'), 'Default rules.')
    end

    it 'only scans configured directories', :aggregate_failures do
      expect(config.skills.map(&:name)).to eq(['review_rules'])
      expect(config.skills.map(&:source)).to all(end_with('.github'))
    end
  end
end
