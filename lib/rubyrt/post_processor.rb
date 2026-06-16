# frozen_string_literal: true

module Rubyrt
  # Filters issues using a Ruby expression from configuration.
  # The expression can reference `issue` which is a Hash representation of the
  # raw issue. It must return a truthy value to keep the issue.
  class PostProcessor
    def initialize(filter_expression)
      @filter_expression = filter_expression
    end

    def call(issues)
      return issues if @filter_expression.nil? || @filter_expression.strip.empty?

      issues.select do |issue|
        context = PostProcessorContext.new(issue)
        context.keep?(@filter_expression)
      end
    end
  end

  # Execution context for the post-processing filter expression.
  class PostProcessorContext
    def initialize(issue)
      @issue = issue.to_h
    end

    attr_reader :issue

    def keep?(expression)
      instance_eval(expression, __FILE__, __LINE__)
    end
  end
end
