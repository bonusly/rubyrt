# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rubyrt::GitHub::Commenter do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:commenter) do
    described_class.new(token: 'token', owner: 'o', repo: 'r', pr_number: 1)
  end

  let(:client) { instance_double(Octokit::Client) }

  let(:pr) { double('pr', head: double('head', sha: 'commit-sha')) } # rubocop:disable RSpec/VerifiedDoubles

  # app.rb hunk covers new-side lines 10-13 (line 11 is an addition).
  # changed.rb hunk covers new-side lines 5-6 (line 6 is an addition).
  let(:pr_files) do
    [
      double('file', filename: 'app.rb', # rubocop:disable RSpec/VerifiedDoubles
                     patch: "@@ -10,3 +10,4 @@\n ctx10\n+added11\n ctx12\n ctx13"),
      double('file', filename: 'changed.rb', # rubocop:disable RSpec/VerifiedDoubles
                     patch: "@@ -5,2 +5,2 @@\n ctx5\n-old\n+added6")
    ]
  end

  before do
    allow(Octokit::Client).to receive(:new).and_return(client)
    allow(client).to receive_messages(
      pull_request: pr,
      pull_request_files: pr_files,
      issue_comments: []
    )
    allow(client).to receive(:create_pull_request_comment)
    # Skip stale-thread resolution; covered elsewhere.
    allow(client).to receive(:user).and_raise(Octokit::Forbidden.new)
  end

  def build_issue(file, start_line)
    raw = Rubyrt::RawIssue.new(title: 'T', severity: 1, confidence: 1, details: 'd', tags: ['bug'])
    range = Rubyrt::AffectedRange.new(start_line: start_line)
    Rubyrt::Issue.new(id: 1, file: file, raw_issue: raw, affected_lines: [range])
  end

  def report_for(issues)
    target = Rubyrt::ReviewTarget.new(platform: 'github', repo_url: nil, pr_number: 1, commit_sha: nil,
                                      branch: nil, base_ref: nil, head_ref: nil, merge_base: false)
    Rubyrt::Report.new(target: target, model: 'm', issues: issues)
  end

  it 'posts an inline comment when the line is part of the diff' do
    commenter.post_review(summary: 'S', report: report_for([build_issue('app.rb', 11)]))

    expect(client).to have_received(:create_pull_request_comment)
      .with('o/r', 1, anything, 'commit-sha', 'app.rb', nil, { line: 11, side: 'RIGHT' })
  end

  it 'falls back to a file-level comment when the line is outside the diff hunks' do
    commenter.post_review(summary: 'S', report: report_for([build_issue('app.rb', 999)]))

    expect(client).to have_received(:create_pull_request_comment)
      .with('o/r', 1, anything, 'commit-sha', 'app.rb', nil, { subject_type: 'file' })
  end

  it 'skips files that are not part of the PR diff' do
    commenter.post_review(summary: 'S', report: report_for([build_issue('untouched.rb', 5)]))

    expect(client).not_to have_received(:create_pull_request_comment)
  end

  it 'degrades to inline posting when the PR diff cannot be fetched' do
    allow(client).to receive(:pull_request_files).and_raise(Octokit::Error.new)

    commenter.post_review(summary: 'S', report: report_for([build_issue('app.rb', 999)]))

    expect(client).to have_received(:create_pull_request_comment)
      .with('o/r', 1, anything, 'commit-sha', 'app.rb', nil, { line: 999, side: 'RIGHT' })
  end
end
