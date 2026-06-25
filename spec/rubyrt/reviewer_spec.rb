# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Rubyrt::Reviewer do
  subject(:reviewer) do
    described_class.new(
      config: config,
      changeset: fake_changeset,
      prompt_builder: Rubyrt::PromptBuilder.new(config),
      llm_client: fake_llm_client
    )
  end

  let(:tmp_dir) { Dir.mktmpdir }
  let(:config) { Rubyrt::Configuration.new(root: tmp_dir) }
  let(:fake_changeset) do
    instance_double(Rubyrt::Changeset,
                    files: ['app.rb'],
                    diff_text_for: "+ def hello\n",
                    full_content_for: "def hello\nend\n",
                    changed_lines_for: Set.new([1]),
                    base_ref: 'main',
                    head_ref: 'HEAD')
  end
  let(:fake_llm_client) do
    issues = [{ 'title' => 'Missing return', 'details' => 'No return value', 'severity' => 2,
                'confidence' => 1, 'tags' => ['bug'], 'affected_lines' => [{ 'start_line' => 1 }] }]
    response = instance_double(RubyLLM::Message, content: { 'issues' => issues })
    instance_double(Rubyrt::LlmClient, complete_with_schema: response)
  end

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it 'returns a report with parsed issues', :aggregate_failures do
    report = reviewer.review
    expect(report).to be_a(Rubyrt::Report)
    expect(report.total_issues).to eq(1)
    expect(report.issues.first.title).to eq('Missing return')
    expect(report.issues.first.id).to eq(1)
    expect(report.number_of_processed_files).to eq(1)
  end

  context 'when an issue falls on an unchanged line' do
    let(:fake_changeset) do
      instance_double(Rubyrt::Changeset,
                      files: ['app.rb'],
                      diff_text_for: "+ def hello\n",
                      full_content_for: "def hello\nend\n",
                      changed_lines_for: Set.new([5]), # issue is on line 1, not changed
                      base_ref: 'main',
                      head_ref: 'HEAD')
    end

    it 'drops findings outside the changed lines' do
      expect(reviewer.review.total_issues).to eq(0)
    end
  end

  context 'when the LLM client raises a connection error' do
    let(:connection_error) { Class.new(StandardError) }
    let(:fake_llm_client) do
      instance_double(Rubyrt::LlmClient).tap do |client|
        allow(client).to receive(:complete_with_schema)
          .and_raise(connection_error, 'Failed to open TCP connection')
      end
    end

    it 'propagates the error instead of silently returning no issues' do
      expect do
        reviewer.review
      end.to raise_error(RuntimeError, /Parallel review failures.*Failed to open TCP connection/m)
    end
  end

  context 'when the LLM returns malformed JSON' do
    let(:fake_llm_client) do
      response = instance_double(RubyLLM::Message, content: 'not valid json')
      instance_double(Rubyrt::LlmClient, complete_with_schema: response)
    end

    it 'records a warning and continues with no issues for that file', :aggregate_failures do
      report = reviewer.review
      expect(report.total_issues).to eq(0)
      expect(report.processing_warnings).to include(/Could not parse LLM response for app.rb/)
    end
  end

  context 'when the LLM returns a raw JSON array string (fallback)' do
    let(:fake_llm_client) do
      json = '[{"title":"Bug","details":"desc","severity":1,"confidence":1,' \
             '"tags":[],"affected_lines":[{"start_line":1}]}]'
      response = instance_double(RubyLLM::Message, content: json)
      instance_double(Rubyrt::LlmClient, complete_with_schema: response)
    end

    it 'parses the array response', :aggregate_failures do
      report = reviewer.review
      expect(report.total_issues).to eq(1)
      expect(report.issues.first.title).to eq('Bug')
    end
  end
end
