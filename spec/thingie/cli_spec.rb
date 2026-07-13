# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'thingie/cli'
require 'fileutils'

RSpec.describe Thingie::CLI do
  let(:tmp_dir) { Dir.mktmpdir }

  # Keep the global RubyLLM registry hermetic, and never read a developer's real
  # ~/.rubyrt/.env (which would leak LLM_MODEL into ENV for the whole suite).
  around do |example|
    original_file = RubyLLM.config.model_registry_file
    original_key = RubyLLM.config.openai_api_key
    original_llm_model = ENV.fetch('LLM_MODEL', nil)
    ENV.delete('LLM_MODEL')
    example.run
  ensure
    RubyLLM.config.model_registry_file = original_file
    RubyLLM.config.openai_api_key = original_key
    RubyLLM::Models.instance_variable_set(:@instance, nil)
    original_llm_model ? ENV['LLM_MODEL'] = original_llm_model : ENV.delete('LLM_MODEL')
  end

  before { stub_const('Thingie::Configuration::USER_ENV_FILE', File.join(tmp_dir, 'no-such.env')) }

  after { FileUtils.rm_rf(tmp_dir) }

  def run_models(argv)
    Thingie::CLI.start(['models', *argv])
  end

  context 'when no models_file is configured' do
    let(:config) { Thingie::Configuration.new(root: tmp_dir, overrides: { 'models_file' => '' }) }

    before do
      allow(Thingie::Configuration).to receive(:new).and_return(config)
      allow(RubyLLM.models).to receive(:refresh!)
    end

    it 'exits with a usage message and does not call refresh' do
      expect do
        run_models([])
      end.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }

      expect(RubyLLM.models).not_to have_received(:refresh!)
    end
  end

  context 'when --path is given' do
    let(:models_path) { File.join(tmp_dir, 'nested', 'models.json') }
    let(:config) { Thingie::Configuration.new(root: tmp_dir, overrides: { 'models_file' => models_path }) }

    before do
      allow(Thingie::Configuration).to receive(:new).and_return(config)
      allow(RubyLLM.models).to receive(:refresh!)
      allow(RubyLLM.models).to receive(:save_to_json)
      allow(RubyLLM.models).to receive(:count).and_return(7)
    end

    it 'refreshes the registry and saves it to the configured path' do
      expect do
        run_models(['--path', models_path])
      end.to output(/Saved 7 models to #{Regexp.escape(models_path)}/).to_stdout

      expect(RubyLLM.models).to have_received(:refresh!).with(no_args)
      expect(RubyLLM.models).to have_received(:save_to_json).with(models_path)
      expect(RubyLLM.config.model_registry_file).to eq(models_path)
      expect(File.exist?(File.dirname(models_path))).to be(true)
    end
  end
end
