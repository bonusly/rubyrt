# frozen_string_literal: true

require 'set' # rubocop:disable Lint/RedundantRequireStatement -- explicit for Ruby < 3.2
require 'octokit'

module Rubyrt
  module GitHub
    # Posts RubyRT review results to a GitHub pull request. Resolves stale
    # RubyRT review threads and collapses previous summary comments before
    # posting new feedback.
    class Commenter # rubocop:disable Metrics/ClassLength
      REVIEW_COMMENT_MARKER = '<!-- rubyrt-review-comment -->'

      # Mirrors the default severity_scale in config/default.toml — used only
      # for human-facing labels in comments.
      SEVERITY_LABELS = { 1 => 'Critical', 2 => 'High', 3 => 'Medium', 4 => 'Low' }.freeze

      def initialize(token:, owner:, repo:, pr_number:)
        # auto_paginate so PRs with many files/comments aren't truncated to the
        # first page when validating diff lines or collapsing old summaries.
        @client = Octokit::Client.new(access_token: token, auto_paginate: true)
        @owner = owner
        @repo = repo
        @pr_number = pr_number
      end

      def post_review(summary:, report:)
        pr = @client.pull_request("#{@owner}/#{@repo}", @pr_number)
        commit_id = pr.head.sha
        resolve_previous_threads(report.issues)
        collapse_previous_summaries
        uncommented = post_inline_comments(report.issues, commit_id)
        post_summary_comment(summary, uncommented)
      end

      private

      # Post one inline comment per affected line that falls inside the PR diff.
      # GitHub's review-comment API only accepts line-based comments on diff
      # lines, so issues elsewhere are returned for the summary instead of being
      # forced through the file-level API (which it rejects).
      def post_inline_comments(issues, commit_id)
        issues.reject { |issue| post_issue_inline?(issue, commit_id) }
      end

      def post_issue_inline?(issue, commit_id)
        issue.affected_lines.filter_map do |range|
          next unless range.start_line

          line = range.end_line || range.start_line
          next unless line_in_diff?(issue.file, line)

          create_inline_comment(issue, commit_id, line)
          true
        rescue Octokit::UnprocessableEntity => e
          warn "Could not post comment on #{issue.file}:#{line} — #{e.message}"
          nil
        end.any?
      end

      def create_inline_comment(issue, commit_id, line)
        @client.create_pull_request_comment(
          "#{@owner}/#{@repo}",
          @pr_number,
          issue_body(issue),
          commit_id,
          issue.file,
          line, # Octokit 9: 6th positional is the new-side line number
          { side: 'RIGHT' }
        )
      end

      def post_summary_comment(summary, uncommented)
        body = [summary, uncommented_section(uncommented), Context::SUMMARY_MARKER].compact.join("\n\n")
        @client.add_comment("#{@owner}/#{@repo}", @pr_number, body)
      end

      # Issues outside the diff can't be inline comments, so list them in the
      # summary so the feedback isn't lost.
      def uncommented_section(issues)
        return nil if issues.empty?

        rows = issues.map do |issue|
          line = issue.affected_lines.first&.start_line
          location = line ? ":#{line}" : ''
          "- **#{severity_label(issue.severity)}** `#{issue.file}#{location}` — #{issue.title}"
        end
        "### Other findings (outside this diff)\n\n#{rows.join("\n")}"
      end

      def severity_label(severity)
        SEVERITY_LABELS.fetch(severity, "Severity #{severity}")
      end

      def line_in_diff?(file, line)
        # When the diff can't be fetched, treat nothing as commentable so the
        # issue falls back to the summary rather than risking a 422 per line.
        return false unless commentable_lines

        commentable_lines.fetch(file, Set.new).include?(line)
      end

      # Maps each changed file to the set of new-side line numbers GitHub will
      # accept inline comments on (added and context lines within diff hunks).
      # Returns nil when the diff can't be fetched.
      def commentable_lines
        return @commentable_lines if defined?(@commentable_lines)

        files = @client.pull_request_files("#{@owner}/#{@repo}", @pr_number)
        @commentable_lines = files.each_with_object({}) do |file, hash|
          hash[file.filename] = new_side_lines(file.patch) if file.patch
        end
      rescue Octokit::Error => e
        warn "Could not fetch PR diff to validate comment lines — #{e.message}"
        @commentable_lines = nil
      end

      def new_side_lines(patch)
        lines = Set.new
        new_line = nil
        patch.each_line do |raw|
          line = raw.chomp
          if (match = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)/))
            new_line = match[1].to_i
          # Skip hunk metadata, "\ No newline" markers, and deletions: none of
          # these advance or anchor a new-side line number.
          elsif new_line.nil? || line.start_with?('\\', '-')
            next
          else
            lines << new_line # added ('+') or context (' ') line
            new_line += 1
          end
        end
        lines
      end

      def issue_body(issue)
        tags = "Tags: #{issue.tags.join(', ')}" unless issue.tags.to_a.empty?
        [
          REVIEW_COMMENT_MARKER,
          "**[#{severity_label(issue.severity)}] #{issue.title}**",
          issue.details,
          tags
        ].compact.join("\n\n")
      end

      def resolve_previous_threads(current_issues)
        bot_login = bot_login_from_token
        return unless bot_login

        current_lines = current_issue_lines(current_issues)
        threads = fetch_review_threads
        threads.each do |thread|
          resolve_thread(thread, bot_login, current_lines)
        end
      end

      def current_issue_lines(issues)
        issues.each_with_object({}) do |issue, hash|
          hash[issue.file] ||= []
          issue.affected_lines.each do |range|
            next unless range.start_line

            hash[issue.file] << (range.end_line || range.start_line)
          end
        end
      end

      def bot_login_from_token
        @client.user.login
      rescue Octokit::Forbidden, Octokit::Unauthorized
        # The default GITHUB_TOKEN in Actions can't read /user. This is expected
        # and non-fatal — we just skip resolving stale threads.
        nil
      end

      def graphql_client
        @graphql_client ||= GraphqlClient.new(@client)
      end

      def fetch_review_threads
        graphql_client.review_threads(
          owner: @owner,
          repo: @repo,
          pr_number: @pr_number
        )
      end

      def resolve_thread(thread, bot_login, current_lines)
        return if thread['isResolved']
        return unless rubyrt_thread?(thread, bot_login)
        return if line_still_reported?(thread, current_lines)

        graphql_client.resolve_thread(thread['id'])
      end

      def rubyrt_thread?(thread, bot_login)
        first_comment = thread.dig('comments', 'nodes', 0)
        first_comment &&
          first_comment.dig('author', 'login') == bot_login &&
          first_comment['body'].include?(REVIEW_COMMENT_MARKER)
      end

      def line_still_reported?(thread, current_lines)
        return false if thread['isOutdated']

        path = thread['path']
        line = thread['line']
        return false if path.nil? || line.nil?

        (current_lines[path] || []).include?(line)
      end

      def collapse_previous_summaries
        comments = @client.issue_comments("#{@owner}/#{@repo}", @pr_number)
        comments.each do |comment|
          next unless comment.body.include?(Context::SUMMARY_MARKER)

          @client.update_comment(
            "#{@owner}/#{@repo}",
            comment.id,
            outdated_body(comment.body)
          )
        end
      end

      def outdated_body(body)
        stripped = body.sub(Context::SUMMARY_MARKER, '')
        "<details><summary>Outdated RubyRT summary</summary>\n\n#{stripped}\n\n</details>"
      end
    end
  end
end
