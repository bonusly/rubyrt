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
      @settings = settings || {}
    end

    def call(issues)
      issues.select { |issue| keep?(issue) }
    end

    private

    def keep?(issue)
      hash = issue.to_h
      within?(hash['confidence'], @settings['max_confidence']) &&
        within?(hash['severity'], @settings['max_severity'])
    end

    def within?(value, max)
      return true if max.nil? || value.nil?

      value <= max
    end
  end
end
