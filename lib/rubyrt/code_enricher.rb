# frozen_string_literal: true

module Rubyrt
  # Adds affected code snippets to each issue's affected line ranges.
  class CodeEnricher
    def initialize(changeset)
      @changeset = changeset
    end

    def call(issues)
      issues.each do |issue|
        enrich_issue(issue)
      end
    end

    private

    def enrich_issue(issue)
      lines = lines_for(issue.file)
      issue.affected_lines.each do |range|
        next unless lines.any?

        start_index = (range.start_line || 1) - 1
        end_index = (range.end_line || range.start_line || 1) - 1
        range.instance_variable_set(:@affected_code, lines[start_index..end_index]&.join)
      end
    end

    def lines_for(file)
      content = @changeset.full_content_for(file)
      content ? content.lines : []
    end
  end
end
