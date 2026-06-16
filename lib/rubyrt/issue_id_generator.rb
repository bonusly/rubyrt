# frozen_string_literal: true

module Rubyrt
  # Provides unique issue IDs during a review run.
  class IssueIdGenerator
    def initialize
      @counter = 0
    end

    def next_id
      @counter += 1
    end
  end
end
