# frozen_string_literal: true

require 'async'
require 'async/semaphore'

module Rubyrt
  # Orchestrates reviewing the changeset: builds prompts, calls the LLM,
  # integrates static analysis adapters, post-processes issues, and builds a
  # Report.
  class Reviewer
    def initialize(config:, changeset:, prompt_builder:, llm_client:, adapters: [])
      @config = config
      @changeset = changeset
      @prompt_builder = prompt_builder
      @llm_client = llm_client
      @adapters = adapters
      @warnings = []
      @id_generator = IssueIdGenerator.new
    end

    def review
      issues = gather_llm_issues + gather_adapter_issues
      filtered = PostProcessor.new(@config.dig('post_process', 'filter')).call(issues)
      CodeEnricher.new(@changeset).call(filtered)
      Report.new(
        target: build_target,
        model: @config['model'],
        issues: filtered,
        processing_warnings: @warnings,
        number_of_processed_files: @changeset.files.size
      )
    end

    private

    def gather_llm_issues
      files = @changeset.files
      concurrency = [@config['max_concurrent_tasks'] || 10, 1].max
      return files.flat_map { |f| review_file(f) } if concurrency == 1

      review_in_parallel(files, concurrency)
    end

    def review_in_parallel(files, concurrency)
      results = Array.new(files.size)
      errors = []
      semaphore = Async::Semaphore.new(concurrency)

      Sync do
        files.each_with_index do |file, index|
          semaphore.async do
            results[index] = review_file(file)
          rescue StandardError => e
            errors << e
          end
        end
      end

      raise errors.first if errors.any?

      results.flatten
    end

    def review_file(file)
      diff = @changeset.diff_text_for(file)
      full = @changeset.full_content_for(file)
      prompt = @prompt_builder.review(diff: diff, file_lines: full)
      response = @llm_client.complete_with_schema(prompt, Schemas::ISSUE_SCHEMA)
      parse_response(response, file)
    rescue JSON::ParserError => e
      @warnings << "Could not parse LLM response for #{file}: #{e.message}"
      []
    end

    def parse_response(response, file)
      return [] if response.nil?

      content = response.content
      issues = extract_issues(content)
      IssueParser.new(@id_generator).parse(issues, file)
    end

    def extract_issues(content)
      return [] if content.nil? || (content.is_a?(String) && content.strip.empty?)

      parsed = content.is_a?(String) ? JSON.parse(content) : content
      parsed.is_a?(Array) ? parsed : parsed['issues'] || []
    end

    def gather_adapter_issues
      return [] if @adapters.empty?

      @adapters.flat_map { |adapter| adapter.call(@changeset.files) }.map do |file, raw|
        Issue.new(
          id: @id_generator.next_id,
          file: file,
          raw_issue: raw,
          affected_lines: raw.affected_lines
        )
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
