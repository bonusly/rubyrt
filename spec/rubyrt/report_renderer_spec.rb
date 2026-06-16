# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rubyrt::ReportRenderer do
  subject(:renderer) { described_class.new(report) }

  let(:report) do
    Rubyrt::Report.new(
      target: Rubyrt::ReviewTarget.new(
        platform: 'local', repo_url: nil, pr_number: nil, commit_sha: nil,
        branch: nil, base_ref: 'main', head_ref: 'HEAD', merge_base: false
      ),
      model: 'gpt-4o',
      issues: [
        Rubyrt::Issue.new(
          id: 1,
          file: 'app.rb',
          raw_issue: Rubyrt::RawIssue.new(
            title: 'Unused variable',
            severity: 2,
            confidence: 1,
            details: 'x is assigned but never used',
            tags: ['maintainability'],
            affected_lines: [Rubyrt::AffectedRange.new(start_line: 3, end_line: 3)]
          ),
          affected_lines: [Rubyrt::AffectedRange.new(start_line: 3, end_line: 3)]
        )
      ]
    )
  end

  it 'renders CLI output', :aggregate_failures do
    output = renderer.to_cli
    expect(output).to include('1 issue(s) found')
    expect(output).to include('Unused variable')
    expect(output).to include('app.rb')
  end

  it 'renders Markdown output', :aggregate_failures do
    output = renderer.to_md
    expect(output).to include('RubyRT Code Review')
    expect(output).to include('Unused variable')
    expect(output).to include('app.rb')
  end

  context 'with no issues but processed files' do
    let(:report) do
      Rubyrt::Report.new(
        target: Rubyrt::ReviewTarget.new(
          platform: 'local', repo_url: nil, pr_number: nil, commit_sha: nil,
          branch: nil, base_ref: 'main', head_ref: 'HEAD', merge_base: false
        ),
        model: 'gpt-4o',
        issues: [],
        number_of_processed_files: 5
      )
    end

    it 'reports the number of processed files in CLI output' do
      expect(renderer.to_cli).to include('No issues found across 5 file(s)')
    end

    it 'reports the number of processed files in Markdown output' do
      expect(renderer.to_md).to include('**✅ No issues found** across 5 file(s)')
    end
  end
end
