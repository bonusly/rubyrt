# frozen_string_literal: true

require 'octokit'
require_relative 'commenter' # SEVERITY_BY_LABEL is built from Commenter::SEVERITY_LABELS at load time
require_relative 'graphql_client'

module Rubyrt
  module GitHub
    # Optionally approves a pull request when a configurable set of safety rules
    # all pass. Runs after Commenter#post_review and is disabled unless
    # approve.enabled is set in config. Reads happen on the main token; the
    # approval (and any dismissal) is attempted in order: workflow token
    # (GITHUB_TOKEN), app/main token, then resolve-token user (PAT).
    class Approver # rubocop:disable Metrics/ClassLength
      APPROVAL_MARKER = '<!-- rubyrt-approval -->'
      # Never auto-approve a PR that edits RubyRT's own config — that's how
      # someone would weaken the approval rules to wave their change through.
      CONFIG_PATH = '.rubyrt/config.toml'
      DEFAULT_MAX_CHANGES = 500
      DEFAULT_MAX_SEVERITY = 3
      DEFAULT_SKIP_LABEL = 'rubyrt-skip-approve'

      # Inverse of Commenter::SEVERITY_LABELS, to read a thread's severity back
      # out of the comment body RubyRT wrote (e.g. "[Critical]").
      SEVERITY_BY_LABEL = Commenter::SEVERITY_LABELS.invert.freeze

      Decision = Struct.new(:action, :reasons)

      def initialize(token:, owner:, repo:, pr_number:, config: {}, workflow_token: nil, resolve_token: nil)
        # Reads use the main token. Approvals are tried in order: workflow token
        # (GITHUB_TOKEN), app/main token, resolve-token PAT. Empty env vars are
        # treated as unset.
        workflow_token = nil if workflow_token.to_s.strip.empty?
        resolve_token = nil if resolve_token.to_s.strip.empty?
        @workflow_client = workflow_token && Octokit::Client.new(access_token: workflow_token, auto_paginate: true)
        @client = Octokit::Client.new(access_token: token, auto_paginate: true)
        @resolve_client = resolve_token && Octokit::Client.new(access_token: resolve_token, auto_paginate: true)
        @owner = owner
        @repo = repo
        @pr_number = pr_number
        @config = config || {}
      end

      # Evaluate the rules and approve / dismiss accordingly. Never raises into
      # the run: a failure here must not fail the review that already posted.
      def run(report)
        pr = @client.pull_request(slug, @pr_number)
        decision = decide(pr, report)
        log(decision)
        apply(pr, decision)
      rescue StandardError => e
        warn "Auto-approval skipped — #{e.message}"
      end

      private

      def slug
        "#{@owner}/#{@repo}"
      end

      def max_changes
        @config.fetch('max_changes', DEFAULT_MAX_CHANGES)
      end

      def max_severity
        @config.fetch('max_severity', DEFAULT_MAX_SEVERITY)
      end

      def skip_label
        @config.fetch('skip_label', DEFAULT_SKIP_LABEL)
      end

      def dry_run?
        @config['dry_run'] ? true : false
      end

      # Skip (leave existing approvals alone) for intentional non-approvals;
      # block (dismiss any stale approval) when a rule fails.
      def decide(pr, report)
        return skip("skip label '#{skip_label}' present") if labelled_skip?(pr)
        return skip('PR is a draft') if pr.draft
        return skip('approving identity is the PR author') if self_approval?(pr)

        reasons = block_reasons(pr, report)
        reasons.empty? ? approve : blocked(reasons)
      end

      def block_reasons(pr, report)
        threads = rubyrt_threads
        reasons = []
        reasons << "#{CONFIG_PATH} was changed in this PR" if config_changed?
        reasons << 'a protected path was changed in this PR' if protected_path_changed?
        reasons << "PR has #{change_count(pr)} changes (max #{max_changes})" if too_many_changes?(pr)
        reasons << 'new findings at or above the approval severity threshold' if current_issues?(report)
        reasons << 'unresolved RubyRT findings remain' if unresolved?(threads)
        reasons << 'RubyRT findings were resolved by the author or a contributor' if self_resolved?(threads, pr)
        reasons
      end

      def approve
        Decision.new(:approve, [])
      end

      def blocked(reasons)
        Decision.new(:block, reasons)
      end

      def skip(reason)
        Decision.new(:skip, Array(reason))
      end

      def labelled_skip?(pr)
        Array(pr.labels).any? { |label| label_name(label) == skip_label }
      end

      def label_name(label)
        label.respond_to?(:name) ? label.name : label['name']
      end

      def self_approval?(pr)
        me = approving_login
        !me.nil? && pr.user&.login == me
      end

      # Tokens that can't read /user (Actions GITHUB_TOKEN, App installation
      # tokens) leave the identity unknown; the GitHub 422 on the approve call is
      # the backstop in that case.
      def approving_login
        @client.user.login
      rescue Octokit::Error
        nil
      end

      def config_changed?
        changed_files.include?(CONFIG_PATH)
      end

      # Block when any changed file matches a configured protected glob (e.g.
      # billing code, sensitive config) — same matching as exclude_files.
      def protected_path_changed?
        patterns = Array(@config['protected_paths'])
        return false if patterns.empty?

        changed_files.any? do |file|
          patterns.any? { |pattern| File.fnmatch?(pattern, file, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
        end
      end

      def changed_files
        @changed_files ||= @client.pull_request_files(slug, @pr_number).map(&:filename)
      end

      def too_many_changes?(pr)
        count = change_count(pr)
        !count.nil? && count > max_changes
      end

      # nil when GitHub doesn't report the size — "ignore if we don't know".
      def change_count(pr)
        additions = pr.additions
        deletions = pr.deletions
        return nil if additions.nil? || deletions.nil?

        additions + deletions
      end

      def current_issues?(report)
        report.issues.any? { |issue| qualifying?(issue.severity) }
      end

      def unresolved?(threads)
        threads.any? { |thread| !thread['isResolved'] && qualifying?(thread_severity(thread)) }
      end

      # Every qualifying RubyRT thread that's resolved must have been resolved by
      # someone who is neither the PR author nor a contributor. Unknown resolver
      # (e.g. deleted account) fails safe.
      def self_resolved?(threads, pr)
        insiders = insider_logins(pr)
        threads.any? do |thread|
          next false unless thread['isResolved'] && qualifying?(thread_severity(thread))

          resolver = thread.dig('resolvedBy', 'login')
          resolver.nil? || insiders.include?(resolver)
        end
      end

      # PR author plus everyone who authored or committed code in the PR. Does
      # not cover Co-authored-by trailers (not real commit identities).
      def insider_logins(pr)
        logins = [pr.user&.login]
        @client.pull_request_commits(slug, @pr_number).each do |commit|
          logins << commit.author&.login
          logins << commit.committer&.login
        end
        logins.compact.uniq
      end

      # Treat unknown severity as qualifying so an unparseable thread fails safe.
      def qualifying?(severity)
        severity.nil? || severity <= max_severity
      end

      def rubyrt_threads
        GraphqlClient.new(@client)
                     .review_threads(owner: @owner, repo: @repo, pr_number: @pr_number)
                     .select { |thread| rubyrt_thread?(thread) }
      end

      def rubyrt_thread?(thread)
        thread.dig('comments', 'nodes', 0, 'body').to_s.include?(Commenter::REVIEW_COMMENT_MARKER)
      end

      def thread_severity(thread)
        body = thread.dig('comments', 'nodes', 0, 'body').to_s
        label = body[/\[([A-Za-z]+)\]/, 1]
        SEVERITY_BY_LABEL[label]
      end

      def apply(pr, decision)
        return if dry_run?

        case decision.action
        when :approve then ensure_approved(pr)
        when :block then dismiss_stale
        end
      end

      def ensure_approved(pr)
        return if approved_for?(pr.head.sha)

        # Workflow token first, app/main token second, PAT last.
        attempt_with_fallback('approve PR') do |client|
          client.create_pull_request_review(slug, @pr_number, event: 'APPROVE', body: approval_body)
        end
      end

      def approval_body
        "#{APPROVAL_MARKER}\n\nApproved automatically by RubyRT: all auto-approval rules passed."
      end

      def dismiss_stale
        rubyrt_approvals.each do |review|
          attempt_with_fallback("dismiss stale approval ##{review.id}") do |client|
            client.dismiss_pull_request_review(slug, @pr_number, review.id,
                                               'RubyRT auto-approval no longer applies.')
          end
        end
      end

      # Try each write client in order; return on the first success. If they all
      # fail, warn with the last error rather than failing the run.
      def attempt_with_fallback(action)
        last_error = nil
        [@workflow_client, @client, @resolve_client].compact.each do |client|
          return yield(client)
        rescue Octokit::Error => e
          last_error = e
        end
        warn "Could not #{action} — #{last_error&.message}"
      end

      def approved_for?(sha)
        rubyrt_approvals.any? { |review| review.commit_id == sha }
      end

      def rubyrt_approvals
        @client.pull_request_reviews(slug, @pr_number).select do |review|
          review.state == 'APPROVED' && review.body.to_s.include?(APPROVAL_MARKER)
        end
      end

      def log(decision)
        prefix = dry_run? ? '[dry-run] ' : ''
        if decision.action == :approve
          warn "#{prefix}RubyRT auto-approval: approving PR ##{@pr_number}."
        else
          warn "#{prefix}RubyRT auto-approval: #{decision.action} — #{decision.reasons.join('; ')}."
        end
      end
    end
  end
end
