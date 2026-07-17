# frozen_string_literal: true

module Thingie
  # Filters issues using simple numeric thresholds from configuration.
  # Lower numbers are more severe / more confident, so an issue is kept when
  # its confidence and severity are at or below the configured maximums.
  #
  # Uses plain comparisons rather than evaluating a config-supplied Ruby
  # expression, which avoids arbitrary code execution at the config boundary.
  class PostProcessor
    # Builds a filter from the `[post_process]` config section.
    #
    # @param settings [Hash, nil] the `[post_process]` config section, e.g. `max_confidence`/`max_severity`
    def initialize(settings)
      settings = (settings || {}).transform_keys(&:to_s)
      # Parse thresholds once; an absent/invalid value means "no limit".
      @max_confidence = Threshold.parse(settings['max_confidence'])
      @max_severity = Threshold.parse(settings['max_severity'])
    end

    # Keep only the issues at or below the configured `max_confidence`/`max_severity` thresholds.
    #
    # @param issues [Array<Thingie::Issue>] issues to filter
    # @return [Array<Thingie::Issue>] the surviving issues
    def call(issues)
      issues.select { |issue| keep?(issue) }
    end

    private

    def keep?(issue)
      within?(issue.confidence, @max_confidence) && within?(issue.severity, @max_severity)
    end

    def within?(value, max)
      return true if max.nil?

      value_int = Integer(value, exception: false)
      value_int.nil? || value_int <= max
    end
  end
end
