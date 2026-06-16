# frozen_string_literal: true

require 'octokit'

module Rubyrt
  module GitHub
    # Posts RubyRT review results to a GitHub pull request.
    class Commenter
      def initialize(token:, owner:, repo:, pr_number:)
        @client = Octokit::Client.new(access_token: token)
        @owner = owner
        @repo = repo
        @pr_number = pr_number
      end

      def post_review(summary:, report:)
        pr = @client.pull_request("#{@owner}/#{@repo}", @pr_number)
        commit_id = pr.head.sha
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
        ["**#{issue.title}**", issue.details, "Tags: #{issue.tags.join(', ')}"].compact.join("\n\n")
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
