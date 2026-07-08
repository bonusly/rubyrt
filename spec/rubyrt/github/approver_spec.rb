# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rubyrt::GitHub::Approver do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:approver) do
    described_class.new(token: 'token', owner: 'o', repo: 'r', pr_number: 1, config: config)
  end

  let(:config) { { 'enabled' => true } }
  let(:client) { instance_double(Octokit::Client) }

  # rubocop:disable RSpec/VerifiedDoubles
  let(:pr) do
    double('pr', draft: false, additions: 10, deletions: 20,
                 head: double('head', sha: 'sha1'), user: double('user', login: 'author'),
                 labels: [])
  end
  # rubocop:enable RSpec/VerifiedDoubles

  # Default: no threads. Per-example overrides stub :post with thread nodes.
  before do
    allow(Octokit::Client).to receive(:new).and_return(client)
    allow(client).to receive_messages(
      pull_request: pr,
      pull_request_commits: [],
      pull_request_files: [],
      pull_request_reviews: [],
      user: double('me', login: 'rubyrt-bot'), # rubocop:disable RSpec/VerifiedDoubles
      post: threads_response([])
    )
    allow(client).to receive(:create_pull_request_review)
    allow(client).to receive(:dismiss_pull_request_review)
  end

  def threads_response(nodes)
    { 'data' => { 'repository' => { 'pullRequest' => { 'reviewThreads' => { 'nodes' => nodes } } } } }
  end

  def stub_threads(nodes)
    allow(client).to receive(:post).and_return(threads_response(nodes))
  end

  def rubyrt_thread(severity: 'Critical', resolved: false, resolved_by: nil)
    {
      'id' => 'T1', 'isResolved' => resolved, 'isOutdated' => false, 'line' => 1, 'path' => 'a.rb',
      'resolvedBy' => resolved_by && { 'login' => resolved_by },
      'comments' => { 'nodes' => [{ 'author' => { 'login' => 'rubyrt-bot' },
                                    'body' => "#{Rubyrt::GitHub::Commenter::REVIEW_COMMENT_MARKER} [#{severity}] x" }] }
    }
  end

  def report_for(issues)
    target = Rubyrt::ReviewTarget.new(platform: 'github', repo_url: nil, pr_number: 1, commit_sha: nil,
                                      branch: nil, base_ref: nil, head_ref: nil, merge_base: false)
    Rubyrt::Report.new(target: target, model: 'm', issues: issues)
  end

  def build_issue(severity)
    raw = Rubyrt::RawIssue.new(title: 'T', severity: severity, confidence: 1, details: 'd', tags: [])
    Rubyrt::Issue.new(id: 1, file: 'a.rb', raw_issue: raw, affected_lines: [])
  end

  def stub_commit_authors(*logins)
    commits = logins.map { |login| double('c', author: double('a', login: login), committer: nil) } # rubocop:disable RSpec/VerifiedDoubles
    allow(client).to receive(:pull_request_commits).and_return(commits)
  end

  def stub_commit_messages(*messages)
    commits = messages.map do |message|
      double('c', author: nil, committer: nil, commit: double('gc', message: message)) # rubocop:disable RSpec/VerifiedDoubles
    end
    allow(client).to receive(:pull_request_commits).and_return(commits)
  end

  def stub_existing_approval(commit_id:, id: 99)
    review = double('rev', id: id, state: 'APPROVED', commit_id: commit_id, # rubocop:disable RSpec/VerifiedDoubles
                           body: described_class::APPROVAL_MARKER)
    allow(client).to receive(:pull_request_reviews).and_return([review])
  end

  it 'approves a clean PR with the approval marker' do
    approver.run(report_for([]))

    expect(client).to have_received(:create_pull_request_review)
      .with('o/r', 1, hash_including(event: 'APPROVE', body: a_string_including(described_class::APPROVAL_MARKER)))
  end

  it 'blocks when the PR exceeds the change limit' do
    allow(pr).to receive_messages(additions: 600, deletions: 0)
    approver.run(report_for([]))

    expect(client).not_to have_received(:create_pull_request_review)
  end

  it 'ignores the change limit when GitHub does not report the size' do
    allow(pr).to receive_messages(additions: nil, deletions: nil)
    approver.run(report_for([]))

    expect(client).to have_received(:create_pull_request_review)
  end

  it 'blocks when the PR changes the RubyRT config' do
    allow(client).to receive(:pull_request_files)
      .and_return([double('file', filename: '.rubyrt/config.toml')]) # rubocop:disable RSpec/VerifiedDoubles
    approver.run(report_for([]))

    expect(client).not_to have_received(:create_pull_request_review)
  end

  it 'blocks when a changed file matches a protected glob' do
    config['protected_paths'] = ['app/billing/**']
    allow(client).to receive(:pull_request_files)
      .and_return([double('file', filename: 'app/billing/charge.rb')]) # rubocop:disable RSpec/VerifiedDoubles
    approver.run(report_for([]))

    expect(client).not_to have_received(:create_pull_request_review)
  end

  it 'approves when changed files do not match any protected glob' do
    config['protected_paths'] = ['app/billing/**']
    allow(client).to receive(:pull_request_files)
      .and_return([double('file', filename: 'app/models/user.rb')]) # rubocop:disable RSpec/VerifiedDoubles
    approver.run(report_for([]))

    expect(client).to have_received(:create_pull_request_review)
  end

  it 'blocks when the current run has a qualifying finding' do
    approver.run(report_for([build_issue(2)]))

    expect(client).not_to have_received(:create_pull_request_review)
  end

  it 'approves when the current run only has a finding below the threshold' do
    approver.run(report_for([build_issue(4)]))

    expect(client).to have_received(:create_pull_request_review)
  end

  it 'blocks on an unresolved qualifying RubyRT thread' do
    stub_threads([rubyrt_thread(resolved: false)])
    approver.run(report_for([]))

    expect(client).not_to have_received(:create_pull_request_review)
  end

  it 'blocks when a qualifying thread was resolved by the PR author' do
    stub_threads([rubyrt_thread(resolved: true, resolved_by: 'author')])
    approver.run(report_for([]))

    expect(client).not_to have_received(:create_pull_request_review)
  end

  it 'blocks when a qualifying thread was resolved by a contributor' do
    stub_commit_authors('dev')
    stub_threads([rubyrt_thread(resolved: true, resolved_by: 'dev')])
    approver.run(report_for([]))

    expect(client).not_to have_received(:create_pull_request_review)
  end

  it 'approves when a qualifying thread was resolved by an independent reviewer' do
    stub_threads([rubyrt_thread(resolved: true, resolved_by: 'reviewer')])
    approver.run(report_for([]))

    expect(client).to have_received(:create_pull_request_review)
  end

  it 'blocks when a qualifying thread was resolved by a Co-authored-by GitHub noreply co-author' do
    stub_commit_messages("Add feature\n\nCo-authored-by: Dev <123+dev@users.noreply.github.com>")
    stub_threads([rubyrt_thread(resolved: true, resolved_by: 'dev')])
    approver.run(report_for([]))

    expect(client).not_to have_received(:create_pull_request_review)
  end

  it 'approves when a co-author uses a non-GitHub email that cannot be mapped to a login' do
    stub_commit_messages("Add feature\n\nCo-authored-by: Dev <dev@example.com>")
    stub_threads([rubyrt_thread(resolved: true, resolved_by: 'dev')])
    approver.run(report_for([]))

    expect(client).to have_received(:create_pull_request_review)
  end

  it 'skips a PR carrying the skip label' do
    allow(pr).to receive(:labels).and_return([double('l', name: 'rubyrt-skip-approve')]) # rubocop:disable RSpec/VerifiedDoubles
    approver.run(report_for([]))

    expect(client).not_to have_received(:create_pull_request_review)
  end

  it 'skips a draft PR' do
    allow(pr).to receive(:draft).and_return(true)
    approver.run(report_for([]))

    expect(client).not_to have_received(:create_pull_request_review)
  end

  it 'skips when the approving identity is the PR author' do
    allow(client).to receive(:user).and_return(double('me', login: 'author')) # rubocop:disable RSpec/VerifiedDoubles
    approver.run(report_for([]))

    expect(client).not_to have_received(:create_pull_request_review)
  end

  it 'does not approve in dry-run mode' do
    config['dry_run'] = true
    approver.run(report_for([]))

    expect(client).not_to have_received(:create_pull_request_review)
  end

  it 'does not duplicate an approval already present for the head SHA' do
    stub_existing_approval(commit_id: 'sha1')
    approver.run(report_for([]))

    expect(client).not_to have_received(:create_pull_request_review)
  end

  it 'dismisses a stale RubyRT approval when a rule now fails' do
    allow(pr).to receive_messages(additions: 600, deletions: 0)
    stub_existing_approval(commit_id: 'old', id: 99)
    approver.run(report_for([]))

    expect(client).to have_received(:dismiss_pull_request_review).with('o/r', 1, 99, anything)
  end

  context 'when the main token cannot approve and a PAT fallback is configured' do
    subject(:approver) do
      described_class.new(token: 'gh', owner: 'o', repo: 'r', pr_number: 1, config: config, resolve_token: 'pat')
    end

    let(:pat_client) { instance_double(Octokit::Client) }

    before do
      allow(Octokit::Client).to receive(:new).with(hash_including(access_token: 'pat')).and_return(pat_client)
      allow(client).to receive(:create_pull_request_review).and_raise(Octokit::Forbidden)
      allow(pat_client).to receive(:create_pull_request_review)
    end

    it 'falls back to the PAT after the main token approval fails', :aggregate_failures do
      approver.run(report_for([]))

      expect(client).to have_received(:create_pull_request_review)
      expect(pat_client).to have_received(:create_pull_request_review).with('o/r', 1, anything)
    end
  end
end
