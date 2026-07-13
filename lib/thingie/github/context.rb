# frozen_string_literal: true

require 'json'

module Thingie
  module GitHub
    # Helper to read repository and PR context from GitHub Actions environment.
    class Context
      SUMMARY_MARKER = '<!-- rubyrt-summary -->'

      def self.from_env
        new(
          repo: ENV.fetch('GITHUB_REPOSITORY', nil),
          event_path: ENV.fetch('GITHUB_EVENT_PATH', nil),
          workflow_pr: ENV.fetch('PR_NUMBER_FROM_WORKFLOW_DISPATCH', nil)
        )
      end

      attr_reader :repo, :event_path, :workflow_pr

      def initialize(repo:, event_path:, workflow_pr:)
        @repo = repo
        @event_path = event_path
        @workflow_pr = workflow_pr
      end

      def pr_number
        raw = @workflow_pr unless @workflow_pr.nil? || @workflow_pr.to_s.strip.empty?
        raw ||= event_payload&.dig('pull_request', 'number')
        raw && Integer(raw, exception: false)
      end

      def owner
        repo&.split('/')&.first
      end

      def repo_name
        repo&.split('/')&.last
      end

      private

      def event_payload
        return @event_payload if defined?(@event_payload)

        @event_payload =
          (JSON.parse(File.read(@event_path)) if @event_path && File.file?(@event_path))
      end
    end
  end
end
