# frozen_string_literal: true

require 'json'
require 'async'
require 'async/semaphore'
require 'async/barrier'
require 'kernel/sync'

module Rubyrt
  # Orchestrates reviewing the changeset: builds prompts, calls the LLM,
  # post-processes issues, and builds a Report.
  class Reviewer
    def initialize(config:, changeset:, prompt_builder:, llm_client:, tools: [])
      @config = config
      @changeset = changeset
      @prompt_builder = prompt_builder
      @llm_client = llm_client
      @tools = tools
      # Plain array: Async runs fibers cooperatively on a single thread, so
      # appends between scheduler yields do not race. No lock needed.
      @warnings = []
    end

    def review
      issues = gather_llm_issues
      filtered = PostProcessor.new(@config['post_process']).call(issues)
      enriched = CodeEnricher.new(@changeset).call(filtered)
      sorted = enriched.sort_by { |issue| issue.severity || Float::INFINITY }
      assign_issue_ids(sorted)
      Report.new(
        target: build_target,
        model: @config['model'],
        issues: sorted,
        processing_warnings: @warnings,
        number_of_processed_files: @changeset.files.size
      )
    end

    private

    def gather_llm_issues
      files = @changeset.files
      concurrency = [@config['max_concurrent_tasks'] || 10, 1].max
      # Always go through the parallel path (a concurrency of 1 runs serially)
      # so error aggregation is identical regardless of concurrency.
      review_in_parallel(files, concurrency)
    end

    def review_in_parallel(files, concurrency) # rubocop:disable Metrics/AbcSize
      results = Array.new(files.size)
      errors = []
      barrier = nil # declared here so it's in scope for the ensure block below

      # Sync (not Async) so the block always blocks until the barrier is
      # drained, even when invoked inside an existing reactor. Async would
      # return the scheduled task immediately and race ahead to results.
      # Barrier/semaphore are created inside the reactor so they bind to it.
      Sync do
        barrier = Async::Barrier.new
        semaphore = Async::Semaphore.new(concurrency, parent: barrier)
        files.each_with_index do |file, index|
          semaphore.async(parent: barrier) do
            results[index] = review_file(file)
          rescue StandardError => e
            errors << [file, e]
          end
        end
        barrier.wait # drain on normal path; wait can raise and mask errors in ensure
      ensure
        barrier&.stop
      end

      if errors.any?
        message = errors.map { |file, e| "#{file}: #{e.class}: #{e.message}" }.join("\n")
        raise "Parallel review failures (#{errors.size} files):\n#{message}"
      end

      results.flatten(1)
    end

    def review_file(file)
      diff = @changeset.diff_text_for(file)
      full = @changeset.full_content_for(file)
      prompt = @prompt_builder.review(diff: diff, file_lines: full)
      response = @llm_client.complete_with_schema(prompt, Schemas::ISSUE_SCHEMA, tools: @tools)
      only_changed_lines(parse_response(response, file), file)
    rescue JSON::ParserError => e
      @warnings << "Could not parse LLM response for #{file}: #{e.message}"
      []
    end

    # The full file is sent to the LLM as context, so it can flag issues on
    # unchanged lines. Drop those: keep only findings touching a changed line,
    # so they don't become off-diff noise in the report and PR comment.
    def only_changed_lines(issues, file)
      changed = @changeset.changed_lines_for(file)
      return issues if changed.nil? # nil = whole-file review (--all), don't filter

      issues.select do |issue|
        issue.affected_lines.any? do |range|
          next false unless range.start_line

          (range.start_line..(range.end_line || range.start_line)).any? { |line| changed.include?(line) }
        end
      end
    end

    def parse_response(response, file)
      return [] if response.nil?

      content = response.content
      issues = extract_issues(content)
      IssueParser.new.parse(issues, file)
    end

    def extract_issues(content)
      return [] if content.nil? || (content.is_a?(String) && content.strip.empty?)

      issues_from(content.is_a?(String) ? JSON.parse(content) : content)
    end

    def issues_from(parsed)
      return parsed if parsed.is_a?(Array)
      return parsed['issues'] || parsed[:issues] || [] if parsed.is_a?(Hash)

      []
    end

    def assign_issue_ids(issues)
      issues.each_with_index do |issue, index|
        issue.id = index + 1
      end
    end

    def build_target
      ReviewTarget.new(
        platform: 'local',
        repo_url: nil,
        pr_number: nil,
        commit_sha: nil,
        branch: nil,
        base_ref: @changeset.base_ref,
        head_ref: @changeset.head_ref,
        merge_base: false
      )
    end
  end
end
