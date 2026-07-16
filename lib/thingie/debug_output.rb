# frozen_string_literal: true

module Thingie
  # Emits debug progress to $stderr when a review runs in debug mode. Kept as a
  # standalone object so the Reviewer stays focused on orchestration: it just
  # calls the appropriate hook methods and this class decides what to print.
  #
  # Section tags: [DEBUG][REVIEW] for per-call initial-review lines,
  # [DEBUG][CRITIC] for per-call critic-pass lines, plain [DEBUG] for summaries.
  class DebugOutput
    def initialize(config:, changeset:, enabled: false)
      @config = config
      @changeset = changeset
      @enabled = enabled
    end

    def banner
      return unless @enabled

      files = @changeset.files
      warn '[DEBUG] Review starting'
      warn "[DEBUG] Model: #{@config['model']} | Provider: #{@config['provider']}"
      critic_model = @config.dig('verify', 'model')
      critic_line = critic_model && !critic_model.to_s.strip.empty? ? critic_model : 'reusing review model'
      warn "[DEBUG] Critic model: #{critic_line}"
      warn "[DEBUG] Files (#{files.size}): #{files.join(', ')}"
    end

    def review_section_start
      return unless @enabled

      warn "[DEBUG] --- Initial Review Pass (#{@changeset.files.size} file(s)) ---"
    end

    # Called after each individual file review LLM call completes.
    def review_call(file:, response:, issues_found:)
      return unless @enabled

      parts = ["#{issues_found} issue(s) found", token_summary(response)]
      cost = cost_summary(response)
      parts << cost if cost
      warn "[DEBUG][REVIEW] #{file}: #{parts.join(' | ')}"
      tool_info = tool_calls_summary(response)
      warn "[DEBUG][REVIEW]   tool calls: #{tool_info}" if tool_info
    end

    def first_pass(issues)
      return unless @enabled

      warn "[DEBUG] First pass: #{issues.size} findings (after threshold + changed-line filters)"
      issues.group_by(&:file).each do |file, file_issues|
        warn "[DEBUG]   #{file}: #{file_issues.size}"
      end
      issues.group_by(&:severity).each do |severity, sev_issues|
        warn "[DEBUG]   Severity distribution: severity=#{severity} -> #{sev_issues.size}"
      end
    end

    def critic_section_start
      return unless @enabled

      warn '[DEBUG] --- Critic Pass ---'
    end

    # Called after each individual critic/verifier LLM call completes.
    def critic_call(issue:, response:, verdict:)
      return unless @enabled

      parts = [token_summary(response)]
      cost = cost_summary(response)
      parts << cost if cost
      warn "[DEBUG][CRITIC] '#{issue.title}' (#{issue.file}) -> #{verdict} | #{parts.join(' | ')}"
      tool_info = tool_calls_summary(response)
      warn "[DEBUG][CRITIC]   tool calls: #{tool_info}" if tool_info
    end

    def critic(input, kept)
      return unless @enabled

      # Issues are compared by object identity (Issue has no == override and
      # the Verifier returns the same objects it received), so Array#- finds
      # exactly the findings the critic dropped.
      dropped = input - kept
      warn "[DEBUG] Critic pass: dropped #{dropped.size} of #{input.size} findings"
      dropped.each do |issue|
        warn "[DEBUG]   DROPPED: '#{issue.title}' (#{issue.file}, severity=#{issue.severity})"
      end
    end

    private

    def token_summary(response)
      input = response&.input_tokens
      output = response&.output_tokens
      return 'tokens: n/a' if input.nil? && output.nil?

      parts = ["#{input || '?'} in", "#{output || '?'} out"]
      parts << "#{input + output} total" if input && output
      cache_read = response&.cache_read_tokens
      parts << "#{cache_read} cache_read" if cache_read&.positive?
      cache_write = response&.cache_write_tokens
      parts << "#{cache_write} cache_write" if cache_write&.positive?
      context = context_window_summary(response, input, output)
      parts << context if context
      "tokens: #{parts.join(' / ')}"
    end

    # RubyLLM doesn't return an actual "context used" figure from the
    # provider — only per-call input/output token counts. This approximates
    # window pressure by comparing input+output against the model's static
    # context_window limit (from the models registry, via response.model_id).
    def context_window_summary(response, input, output)
      return nil unless input && output

      window = response&.model_info&.context_window
      return nil unless window&.positive?

      used = input + output
      format('%<used>d/%<window>d ctx (%<pct>.1f%%)', used: used, window: window, pct: (used * 100.0 / window))
    rescue StandardError
      nil
    end

    def cost_summary(response)
      return nil unless response

      total = response.cost.total
      return nil if total.nil?

      format('cost: $%.6f', total)
    rescue StandardError
      nil
    end

    def tool_calls_summary(response)
      calls = response&.tool_calls
      return nil if calls.nil? || (calls.respond_to?(:empty?) && calls.empty?)

      if calls.is_a?(Hash)
        by_name = calls.values.group_by { |tc| tc.respond_to?(:name) ? tc.name : tc.to_s }
        by_name.map { |name, group| "#{name}(#{group.size})" }.join(', ')
      else
        "#{calls.size} call(s)"
      end
    end
  end
end
