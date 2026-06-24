# frozen_string_literal: true

require 'json'
require 'open3'
require_relative '../models'

module Rubyrt
  module Adapters
    # Runs RuboCop on changed files (via CLI) and normalizes offenses into
    # RawIssue objects with the same schema that the LLM uses.
    class RuboCopAdapter
      SEVERITY_MAP = {
        'fatal' => 1,
        'error' => 1,
        'warning' => 2,
        'convention' => 3,
        'refactor' => 3,
        'info' => 4
      }.freeze

      def call(files)
        return [] if files.empty?

        stdout, stderr, = Open3.capture3('rubocop', '--format', 'json', '--force-exclusion', '--', *files)
        warn stderr unless stderr.empty?

        parsed = JSON.parse(stdout)
        extract_offenses(parsed.fetch('files', []))
      rescue Errno::ENOENT
        []
      rescue StandardError => e
        warn "RuboCop adapter skipped: #{e.message}"
        []
      end

      private

      def extract_offenses(files)
        files.flat_map do |file|
          file.fetch('offenses', []).map do |offense|
            [file['path'], raw_issue_from_offense(offense)]
          end
        end
      end

      def raw_issue_from_offense(offense)
        start_line, end_line = extract_location(offense)
        RawIssue.new(
          title: offense['message'],
          details: "#{offense['cop_name']}: #{offense['message']}",
          severity: SEVERITY_MAP.fetch(offense['severity'], 3),
          confidence: 1,
          tags: ['code-style'],
          affected_lines: [AffectedRange.new(start_line: start_line, end_line: end_line)]
        )
      end

      def extract_location(offense)
        location = offense['location'] || {}
        start_line = location['start_line'] || location['line'] || 1
        [start_line, location['last_line'] || start_line]
      end
    end
  end
end
