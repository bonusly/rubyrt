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
      @settings = (settings || {}).transform_keys(&:to_s)
    end

    def call(issues)
      issues.select { |issue| keep?(issue) }
    end

    private

    def keep?(issue)
      within?(issue.confidence, @settings['max_confidence']) &&
        within?(issue.severity, @settings['max_severity'])
    end

    def within?(value, max)
      max_int = Integer(max, exception: false) if max
      return true if max_int.nil? # no/invalid threshold means no filtering

      value_int = Integer(value, exception: false)
      value_int.nil? || value_int <= max_int
    end
  end
end
