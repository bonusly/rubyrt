# frozen_string_literal: true

require 'mustache'
require 'json'

module Rubyrt
  # Builds prompts for the review LLM by rendering bundled Mustache templates
  # with configuration values and discovered skill fragments.
  class PromptBuilder
    REVIEW_TEMPLATE = File.expand_path('prompts/review.mustache', __dir__)
    SUMMARY_TEMPLATE = File.expand_path('prompts/summary.mustache', __dir__)

    attr_reader :config

    def initialize(config)
      @config = config
    end

    def review(diff:, file_lines: nil)
      Mustache.render(
        File.read(REVIEW_TEMPLATE),
        template_vars.merge(
          'input' => diff,
          'file_lines' => file_lines
        )
      )
    end

    def summary(diff:, issues:)
      Mustache.render(
        File.read(SUMMARY_TEMPLATE),
        template_vars.merge(
          'diff' => diff,
          'issues_json' => issues.to_json
        )
      )
    end

    private

    def template_vars
      @config.prompt_vars.merge(
        'requirements' => all_requirements,
        'json_requirements' => @config.prompt_vars.fetch('json_requirements', ''),
        'summary_requirements' => @config.prompt_vars.fetch('summary_requirements', ''),
        'self_id' => @config.prompt_vars.fetch('self_id', '')
      )
    end

    def all_requirements
      [base_requirements, skill_requirements].compact.join("\n")
    end

    def base_requirements
      @config.prompt_vars.fetch('requirements', '')
    end

    def skill_requirements
      @config.skills.map do |skill|
        "----RULES FROM #{skill.source.upcase} SKILL: #{skill.name}----\n#{skill.content}"
      end.join("\n\n")
    end
  end
end
