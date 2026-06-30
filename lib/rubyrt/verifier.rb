# frozen_string_literal: true

require 'json'
require 'async'
require 'async/semaphore'
require 'async/barrier'
require 'kernel/sync'

module Rubyrt
  # Critic / challenge pass: re-examines each surviving finding with a fresh,
  # adversarially-framed LLM call and drops the ones it can't uphold. Runs only
  # on findings that passed the threshold filter, so cost scales with finding
  # count, not file size.
  #
  # Fail-open: if a verdict can't be obtained or parsed, the finding is KEPT and
  # a warning is recorded — a broken critic must never silently swallow a real
  # bug.
  class Verifier
    attr_reader :warnings

    def initialize(config:, changeset:, prompt_builder:, llm_client:, tools: [], debug_output: nil)
      @config = config
      @changeset = changeset
      @prompt_builder = prompt_builder
      @tools = tools
      @llm_client = verify_client(config, llm_client)
      @debug_output = debug_output
      @warnings = []
    end

    def call(issues)
      return issues if issues.empty? || !enabled?

      concurrency = [@config['max_concurrent_tasks'] || 10, 1].max
      verdicts = verify_in_parallel(issues, concurrency)
      issues.zip(verdicts).select { |_issue, keep| keep }.map(&:first)
    end

    private

    def settings
      base = (@config['verify'] || {}).transform_keys(&:to_s)
      base['enabled'] = %w[true 1].include?(ENV['VERIFY_ENABLED'].to_s.downcase) if ENV.key?('VERIFY_ENABLED')
      base['model'] = ENV['VERIFY_MODEL'] if ENV.key?('VERIFY_MODEL')
      base
    end

    def enabled?
      settings.fetch('enabled', true)
    end

    # Use a dedicated client (same provider/keys) when a critic model is set,
    # otherwise reuse the review client.
    def verify_client(config, llm_client)
      model = settings['model']
      model && !model.to_s.strip.empty? ? LlmClient.new(config, model: model) : llm_client
    end

    # Same Async barrier/semaphore structure as Reviewer#review_in_parallel:
    # results land by index, errors are aggregated, and the block always blocks
    # until the barrier drains.
    def verify_in_parallel(issues, concurrency)
      results = Array.new(issues.size, true)
      barrier = nil
      Sync do
        barrier = Async::Barrier.new
        semaphore = Async::Semaphore.new(concurrency, parent: barrier)
        issues.each_with_index do |issue, index|
          semaphore.async(parent: barrier) { results[index] = uphold?(issue) }
        end
        barrier.wait
      ensure
        barrier&.stop
      end
      results
    end

    def uphold?(issue)
      prompt = @prompt_builder.verify(
        issue: issue,
        diff: @changeset.diff_text_for(issue.file),
        file_lines: @changeset.full_content_for(issue.file),
        symbol_lookup: @tools.any?
      )
      response = @llm_client.complete_with_schema(prompt, Schemas::VERDICT_SCHEMA, tools: @tools)
      verdict = verdict_of(response)
      @debug_output&.critic_call(issue: issue, response: response,
                                 verdict: verdict.nil? || verdict.empty? ? '(no verdict)' : verdict)
      verdict != 'reject'
    rescue StandardError => e
      # Fail open: keep the finding, but surface that the critic didn't run.
      @warnings << "Could not verify finding '#{issue.title}' (#{issue.file}): #{e.class}: #{e.message}"
      true
    end

    def verdict_of(response)
      content = response&.content
      content = JSON.parse(content) if content.is_a?(String)
      return nil unless content.is_a?(Hash)

      value = content['verdict'] || content[:verdict]
      value.to_s.strip.downcase
    end
  end
end
