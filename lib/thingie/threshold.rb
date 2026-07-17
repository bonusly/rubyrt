# frozen_string_literal: true

module Thingie
  # Shared "absent/invalid means no limit" parsing for the numeric thresholds
  # scattered across `post_process`, `approve`, and the prompt-facing threshold
  # text — one place defines what counts as a valid threshold value.
  module Threshold
    # Parses a config value into a threshold integer, or nil when absent/invalid.
    #
    # @param value [Object] a config value, expected to be an integer or numeric string
    # @return [Integer, nil] the parsed threshold, or nil if it does not represent one
    def self.parse(value)
      Integer(value, exception: false)
    end
  end
end
