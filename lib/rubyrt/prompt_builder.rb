# frozen_string_literal: true

require 'mustache'
require 'json'

module Rubyrt
  # Builds prompts for the review LLM by rendering bundled Mustache templates
  # with configuration values and discovered skill fragments.
  class PromptBuilder
    REVIEW_TEMPLATE = File.expand_path('prompts/review.mustache', __dir__)
    VERIFY_TEMPLATE = File.expand_path('prompts/verify.mustache', __dir__)
    SUMMARY_TEMPLATE = File.expand_path('prompts/summary.mustache', __dir__)

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def review(diff:, file_lines: nil, symbol_lookup: false)
      render_template(REVIEW_TEMPLATE, 'input' => diff, 'file_lines' => file_lines,
                                       'symbol_lookup' => symbol_lookup,
                                       'aux_files' => aux_file_contents,
                                       'severity_scale' => format_scale(@config.severity_scale),
                                       'confidence_scale' => format_scale(@config.confidence_scale))
    end

    def verify(issue:, diff:, file_lines: nil, symbol_lookup: false)
      render_template(VERIFY_TEMPLATE, 'input' => diff, 'file_lines' => file_lines,
                                       'symbol_lookup' => symbol_lookup,
                                       'aux_files' => aux_file_contents,
                                       'finding' => format_finding(issue))
    end

    def summary(diff:, issues:)
      render_template(SUMMARY_TEMPLATE, 'diff' => diff, 'issues_json' => issues.to_json)
    end

    private

    def render_template(path, vars)
      Mustache.render(template_cache(path), template_vars.merge(vars))
    end

    def template_cache(path)
      @template_cache ||= {}
      @template_cache[path] ||= File.read(path, encoding: 'UTF-8')
    end

    def template_vars
      prompt_vars.merge(
        'requirements' => all_requirements,
        'json_requirements' => prompt_vars.fetch('json_requirements', ''),
        'summary_requirements' => prompt_vars.fetch('summary_requirements', ''),
        'self_id' => prompt_vars.fetch('self_id', '')
      )
    end

    # Normalize to string keys so symbol-keyed config can't silently miss lookups.
    def prompt_vars
      @prompt_vars ||= @config.prompt_vars.transform_keys(&:to_s)
    end

    def all_requirements
      [base_requirements, skill_requirements].reject(&:empty?).join("\n")
    end

    def base_requirements
      prompt_vars.fetch('requirements', '')
    end

    def skill_requirements
      @config.skills.map do |skill|
        "----RULES FROM #{skill.source.upcase} SKILL: #{skill.name}----\n#{skill.content}"
      end.join("\n\n")
    end

    def aux_file_contents
      @aux_file_contents ||= @config.aux_files.filter_map do |path|
        next unless File.file?(path)

        "----AUXILIARY FILE: #{relative_path(path)}----\n#{File.read(path, encoding: 'UTF-8')}"
      end.join("\n\n")
    end

    def relative_path(path)
      path.to_s.delete_prefix("#{@config.root.to_s.chomp('/')}/")
    end

    # Render a single issue for the critic prompt: title, details, and each
    # affected range with the actual code (set by CodeEnricher before verify).
    def format_finding(issue)
      ranges = issue.affected_lines.map do |range|
        loc = "lines #{range.start_line}-#{range.end_line || range.start_line}"
        code = range.affected_code ? "\n#{range.affected_code}" : ''
        "#{loc}:#{code}"
      end.join("\n")
      tags = Array(issue.tags).join(', ')
      "File: #{issue.file}\nTitle: #{issue.title}\nTags: #{tags}\n" \
        "Details: #{issue.details}\nAffected code:\n#{ranges}"
    end

    def format_scale(scale)
      return '' unless scale.is_a?(Hash) && !scale.empty?

      scale.sort_by { |k, _| k.to_s.to_i }.map { |level, label| "- #{level} — #{label}" }.join("\n")
    end
  end
end
