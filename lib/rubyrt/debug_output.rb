# frozen_string_literal: true

module Rubyrt
  # Emits debug progress to $stderr when a review runs in debug mode. Kept as a
  # standalone object so the Reviewer stays focused on orchestration: it just
  # calls #banner, #first_pass, and #critic at the right points and this class
  # decides what (if anything) to print.
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
  end
end
