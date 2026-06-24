# frozen_string_literal: true

module Rubyrt
  # Filters issues using simple numeric thresholds from configuration.
  # Lower numbers are more severe / more confident, so an issue is kept when
  # its confidence and severity are at or below the configured maximums.
  #
  # Uses plain comparisons rather than evaluating a config-supplied Ruby
  # expression, which avoided arbitrary code execution at the config boundary.
  class PostProcessor
    def initialize(settings)
      settings = (settings || {}).transform_keys(&:to_s)
      # Parse thresholds once; an absent/invalid value means "no limit".
      @max_confidence = Integer(settings['max_confidence'], exception: false)
      @max_severity = Integer(settings['max_severity'], exception: false)
    end

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
