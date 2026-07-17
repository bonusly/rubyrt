# frozen_string_literal: true

module Thingie
  # Adds affected code snippets to each issue's affected line ranges.
  class CodeEnricher
    # @param changeset [Thingie::Changeset] used to fetch the full file content for each issue's file
    def initialize(changeset)
      @changeset = changeset
    end

    # Enrich each issue's affected line ranges with the actual source snippet, in place.
    #
    # @param issues [Array<Thingie::Issue>] issues to enrich
    # @return [Array<Thingie::Issue>] the same issues, mutated with `affected_code` populated
    def call(issues)
      issues.each do |issue|
        enrich_issue(issue)
      end
    end

    private

    def enrich_issue(issue)
      lines = lines_for(issue.file)
      return if lines.empty?

      issue.affected_lines.each do |range|
        start_index = [(range.start_line || 1) - 1, 0].max
        end_index = [(range.end_line || range.start_line || 1) - 1, 0].max
        range.affected_code = lines[start_index..end_index]&.join
      end
    end

    def lines_for(file)
      @lines_cache ||= {}
      @lines_cache[file] ||= begin
        content = @changeset.full_content_for(file)
        content ? content.lines : []
      end
    end
  end
end
