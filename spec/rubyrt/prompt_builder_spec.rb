# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Rubyrt::PromptBuilder do
  subject(:builder) { described_class.new(config) }

  let(:tmp_dir) { Dir.mktmpdir }
  let(:config) { Rubyrt::Configuration.new(root: tmp_dir) }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe '#review' do
    it 'includes the diff input' do
      prompt = builder.review(diff: "class Foo\nend")
      expect(prompt).to include('class Foo')
    end

    it 'includes prompt_vars requirements' do
      prompt = builder.review(diff: '')
      expect(prompt).to include('Treat unclear or incorrect English')
    end

    it 'includes the JSON response requirement' do
      prompt = builder.review(diff: '')
      expect(prompt).to include('RESPOND ONLY WITH VALID JSON')
    end

    context 'with skill fragments' do
      before do
        FileUtils.mkdir_p(File.join(tmp_dir, '.cursor'))
        File.write(File.join(tmp_dir, '.cursor', 'rails.md'), 'Always use strong params.')
      end

      it 'injects discovered skills as requirements', :aggregate_failures do
        prompt = builder.review(diff: '')
        expect(prompt).to match(/RULES FROM .*\.CURSOR SKILL: rails/i)
        expect(prompt).to include('Always use strong params.')
      end
    end

    context 'with aux_files configured' do
      let(:config) do
        Rubyrt::Configuration.new(
          root: tmp_dir,
          overrides: { aux_files: ['docs/conventions.md', 'docs/missing.md'] }
        )
      end

      before do
        FileUtils.mkdir_p(File.join(tmp_dir, 'docs'))
        File.write(File.join(tmp_dir, 'docs', 'conventions.md'), 'Use frozen_string_literal.')
      end

      it 'injects existing aux file contents into the prompt', :aggregate_failures do
        prompt = builder.review(diff: '')
        expect(prompt).to include('AUXILIARY FILE: docs/conventions.md')
        expect(prompt).to include('Use frozen_string_literal.')
      end

      it 'skips missing aux files without error' do
        prompt = builder.review(diff: '')
        expect(prompt).not_to include('missing.md')
      end
    end

    context 'with custom severity and confidence scales' do
      let(:config) do
        Rubyrt::Configuration.new(
          root: tmp_dir,
          overrides: {
            severity_scale: { '1' => 'Blocker', '2' => 'Needs Fix' },
            confidence_scale: { '1' => 'Sure', '2' => 'Guess' }
          }
        )
      end

      it 'renders the custom scales in the prompt', :aggregate_failures do # rubocop:disable RSpec/ExampleLength
        prompt = builder.review(diff: '')
        expect(prompt).to include('- 1 — Blocker')
        expect(prompt).to include('- 2 — Needs Fix')
        expect(prompt).to include('- 1 — Sure')
        expect(prompt).to include('- 2 — Guess')
        expect(prompt).not_to include('Critical')
      end
    end
  end

  describe '#summary' do
    let(:issues) do
      [{ 'title' => 'Unused variable', 'severity' => 2 }]
    end

    it 'renders the summary prompt with issues JSON', :aggregate_failures do
      prompt = builder.summary(diff: 'diff text', issues: issues)
      expect(prompt).to include('Summarize the code review in one sentence')
      expect(prompt).to include('Unused variable')
    end
  end
end
