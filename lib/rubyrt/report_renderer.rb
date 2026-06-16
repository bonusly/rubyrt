# frozen_string_literal: true

require 'json'

module Rubyrt
  # Renders a Rubyrt::Report to Markdown or CLI formats.
  class ReportRenderer
    def initialize(report)
      @report = report
    end

    def to_cli
      output = summary_line
      output += "Summary: #{@report.summary}\n" if @report.summary
      output += @report.issues.map { |issue| render_issue(issue) }.join
      output
    end

    def to_md
      lines = ['<h2>RubyRT Code Review</h2>']
      lines << md_summary_line
      lines << "\n#{@report.summary}" if @report.summary
      lines += @report.issues.map { |issue| md_issue(issue) }
      lines.join("\n")
    end

    private

    def summary_line
      if @report.total_issues.positive?
        "⚠️  #{@report.total_issues} issue(s) found across " \
          "#{@report.number_of_processed_files} file(s).\n"
      else
        "✅ No issues found across #{@report.number_of_processed_files} file(s).\n"
      end
    end

    def md_summary_line
      if @report.total_issues.positive?
        "**⚠️ #{@report.total_issues} issue(s) found** across " \
          "#{@report.number_of_processed_files} file(s)."
      else
        "**✅ No issues found** across #{@report.number_of_processed_files} file(s)."
      end
    end

    def render_issue(issue)
      location = first_location(issue)
      heading = "## [#{issue.id}] #{issue.title}\n  #{issue.file}"
      heading += ":#{location}" if location
      "#{[heading, "  #{issue.details}"].compact.join("\n")}\n"
    end

    def md_issue(issue)
      location = first_location(issue)
      link = location ? "[#{issue.file}:#{location}](#{issue.file})" : issue.file
      lines = ["## ##{issue.id} #{issue.title}", "#{link}\n", issue.details]
      lines << "**Tags:** #{issue.tags.join(', ')}" unless issue.tags.empty?
      lines.compact.join("\n")
    end

    def first_location(issue)
      line = issue.affected_lines.first
      return unless line&.start_line

      if line.end_line && line.end_line != line.start_line
        "L#{line.start_line}-L#{line.end_line}"
      else
        "L#{line.start_line}"
      end
    end
  end
end
