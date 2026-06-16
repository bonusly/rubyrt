# frozen_string_literal: true

require 'octokit'

module Rubyrt
  module GitHub
    # Posts RubyRT review results to a GitHub pull request. Resolves stale
    # RubyRT review threads and collapses previous summary comments before
    # posting new feedback.
    class Commenter
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
        resolve_previous_threads
        collapse_previous_summaries
        post_summary_comment(summary)
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
      end

      def issue_body(issue)
        [
          REVIEW_COMMENT_MARKER,
          "**#{issue.title}**",
          issue.details,
          "Tags: #{issue.tags.join(', ')}"
        ].compact.join("\n\n")
      end

      def resolve_previous_threads
        bot_login = bot_login_from_token
        return unless bot_login

        threads = fetch_review_threads
        threads.each do |thread|
          resolve_thread(thread, bot_login)
        end
      end

      def bot_login_from_token
        @client.user.login
      rescue Octokit::Forbidden => e
        warn "Unable to fetch bot user (token may lack 'user' read scope): #{e.message}"
        nil
      end

      def fetch_review_threads
        GraphqlClient.new(@client).review_threads(
          owner: @owner,
          repo: @repo,
          pr_number: @pr_number
        )
      end

      def resolve_thread(thread, bot_login)
        return if thread['isResolved']

        first_comment = thread.dig('comments', 'nodes', 0)
        return unless first_comment
        return unless first_comment.dig('author', 'login') == bot_login
        return unless first_comment['body'].include?(REVIEW_COMMENT_MARKER)

        GraphqlClient.new(@client).resolve_thread(thread['id'])
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
        "<details><summary>Outdated RubyRT summary</summary>\n\n#{body}\n\n</details>"
      end
    end
  end
end
