# frozen_string_literal: true

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
      @changeset.files.flat_map do |file|
        review_file(file)
      end
    end

    def review_file(file)
      diff = @changeset.diff_text_for(file)
      full = @changeset.full_content_for(file)
      prompt = @prompt_builder.review(diff: diff, file_lines: full)
      response = @llm_client.complete(prompt)
      parse_response(response, file)
    rescue StandardError => e
      @warnings << "Failed to review #{file}: #{e.message}"
      []
    end

    def parse_response(response, file)
      return [] if response.nil? || response.to_s.strip.empty?

      IssueParser.new(@id_generator).parse(JSON.parse(response.to_s), file)
    rescue JSON::ParserError => e
      @warnings << "Could not parse LLM response for #{file}: #{e.message}"
      []
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
