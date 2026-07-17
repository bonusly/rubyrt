# frozen_string_literal: true

require 'erb'
require 'json'

module Thingie
  # Builds prompts for the review LLM by rendering bundled ERB templates with
  # configuration values. Skills are not inlined here — they're exposed to
  # the LLM via SkillCatalog's progressive-disclosure tool instead.
  class PromptBuilder
    REVIEW_TEMPLATE = File.expand_path('prompts/review.erb', __dir__)
    VERIFY_TEMPLATE = File.expand_path('prompts/verify.erb', __dir__)

    # ERB's result_with_hash raises NameError for any var referenced in a
    # template but absent from the hash, so these three (used unconditionally
    # in review.erb/verify.erb) need a default even when prompt_vars omits them.
    DEFAULT_TEMPLATE_VARS = { 'requirements' => '', 'json_requirements' => '', 'self_id' => '' }.freeze

    attr_reader :config

    # Builds a prompt builder backed by the given configuration.
    #
    # @param config [Thingie::Configuration] provides `prompt_vars`, `severity_scale`, and `confidence_scale`
    def initialize(config)
      @config = config
    end

    # Render the review prompt (`review.erb`) for a single file's diff.
    #
    # @param diff [String, nil] the diff text (or full content in `all` mode) to review
    # @param file_lines [String, nil] the full file content, given as extra context to the LLM
    # @param symbol_lookup [Boolean] whether the LSP symbol-lookup tool is available to the LLM
    # @return [String] the rendered prompt text
    def review(diff:, file_lines: nil, symbol_lookup: false)
      render_template(REVIEW_TEMPLATE, 'input' => diff, 'file_lines' => file_lines,
                                       'symbol_lookup' => symbol_lookup,
                                       'severity_scale' => format_scale(@config.severity_scale),
                                       'confidence_scale' => format_scale(@config.confidence_scale))
    end

    # Render the critic/verify prompt (`verify.erb`) that re-checks a single finding.
    #
    # @param issue [Thingie::Issue] the finding to verify
    # @param diff [String, nil] the diff text (or full content in `all` mode) the finding was raised against
    # @param file_lines [String, nil] the full file content, given as extra context to the LLM
    # @param symbol_lookup [Boolean] whether the LSP symbol-lookup tool is available to the LLM
    # @return [String] the rendered prompt text
    def verify(issue:, diff:, file_lines: nil, symbol_lookup: false)
      render_template(VERIFY_TEMPLATE, 'input' => diff, 'file_lines' => file_lines,
                                       'symbol_lookup' => symbol_lookup,
                                       'finding' => format_finding(issue))
    end

    private

    def render_template(path, vars)
      ERB.new(template_cache(path), trim_mode: '-').result_with_hash(template_vars.merge(vars))
    end

    def template_cache(path)
      @template_cache ||= {}
      @template_cache[path] ||= File.read(path, encoding: 'UTF-8')
    end

    def template_vars
      DEFAULT_TEMPLATE_VARS.merge(prompt_vars)
    end

    # Normalize to string keys so symbol-keyed config can't silently miss lookups.
    def prompt_vars
      @prompt_vars ||= @config.prompt_vars.transform_keys(&:to_s)
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
