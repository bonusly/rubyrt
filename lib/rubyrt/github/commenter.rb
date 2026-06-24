# frozen_string_literal: true

require 'octokit'

module Rubyrt
  module GitHub
    # Posts RubyRT review results to a GitHub pull request. Resolves stale
    # RubyRT review threads and collapses previous summary comments before
    # posting new feedback.
    class Commenter # rubocop:disable Metrics/ClassLength
      REVIEW_COMMENT_MARKER = '<!-- rubyrt-review-comment -->'

      def initialize(token:, owner:, repo:, pr_number:)
        @client = Octokit::Client.new(access_token: token)
        @owner = owner
        @repo = repo
        @pr_number = pr_number
      end

      def post_review(summary:, report:)
        pr = @client.pull_request("#{@owner}/#{@repo}", @pr_number)
        commit_id = pr.head.sha
        resolve_previous_threads(report.issues)
        collapse_previous_summaries
        post_summary_comment(summary) if report.issues.empty?
        post_file_comments(report.issues, commit_id)
      end

      private

      def post_summary_comment(summary)
        @client.add_comment(
          "#{@owner}/#{@repo}",
          @pr_number,
          "#{summary}\n\n#{Context::SUMMARY_MARKER}"
        )
      end

      def post_file_comments(issues, commit_id)
        issues.each do |issue|
          issue.affected_lines.each do |range|
            next unless range.start_line

            post_line_comment(issue, commit_id, range)
          end
        end
      end

      def post_line_comment(issue, commit_id, range)
        line = range.end_line || range.start_line
        @client.create_pull_request_comment(
          "#{@owner}/#{@repo}",
          @pr_number,
          issue_body(issue),
          commit_id,
          issue.file,
          line,
          { line: line }
        )
      rescue Octokit::UnprocessableEntity => e
        warn "Could not post comment on #{issue.file}:#{line} — #{e.message}"
      end

      def issue_body(issue)
        [
          REVIEW_COMMENT_MARKER,
          "**#{issue.title}**",
          issue.details,
          "Tags: #{issue.tags.join(', ')}"
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
      rescue Octokit::Forbidden
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
