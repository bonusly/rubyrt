# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Rubyrt::Configuration do
  subject(:config) { described_class.new(root: tmp_dir) }

  let(:tmp_dir) { Dir.mktmpdir }

  it 'loads bundled defaults', :aggregate_failures do
    expect(config['mention_triggers']).to eq(%w[rubyrt bot ai /check])
    expect(config['collapse_previous_code_review_comments']).to be true
    expect(config['retries']).to eq(3)
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

  context 'with environment variables' do
    before do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('LLM_MODEL', anything).and_return('gpt-5')
    end

    it 'overrides model from environment' do
      expect(config['model']).to eq('gpt-5')
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
end
