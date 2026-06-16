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
      llm_client: fake_llm_client,
      adapters: []
    )
  end

  let(:tmp_dir) { Dir.mktmpdir }
  let(:config) { Rubyrt::Configuration.new(root: tmp_dir) }
  let(:fake_changeset) do
    instance_double(Rubyrt::Changeset,
                    files: ['app.rb'],
                    diff_text_for: "+ def hello\n",
                    full_content_for: "def hello\nend\n",
                    base_ref: 'main',
                    head_ref: 'HEAD')
  end
  let(:fake_llm_client) do
    response = '[{"title": "Missing return", "details": "No return value", "severity": 2, ' \
               '"confidence": 1, "tags": ["bug"], "affected_lines": [{"start_line": 1}]}]'
    instance_double(Rubyrt::LlmClient, complete: response)
  end

  after do
    FileUtils.remove_entry(tmp_dir)
  end

  it 'returns a report with parsed issues', :aggregate_failures do
    report = reviewer.review
    expect(report).to be_a(Rubyrt::Report)
    expect(report.total_issues).to eq(1)
    expect(report.issues.first.title).to eq('Missing return')
  end
end
