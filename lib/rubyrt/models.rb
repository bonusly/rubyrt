# frozen_string_literal: true

require 'json'
require 'time'
require 'fileutils'

module Rubyrt
  # Metadata about the code under review.
  ReviewTarget = Data.define(
    :platform,
    :repo_url,
    :pr_number,
    :commit_sha,
    :branch,
    :base_ref,
    :head_ref,
    :merge_base
  ) do
    def github?
      platform == 'github'
    end

    def local?
      platform == 'local'
    end
  end

  # A code range that an issue refers to, optionally with a proposed fix.
  AffectedRange = Struct.new(:start_line, :end_line, :proposal, :affected_code, keyword_init: true) do
    def initialize(start_line:, end_line: start_line, proposal: nil, affected_code: nil)
      super
    end
  end

  # Raw issue returned by the LLM before enrichment.
  RawIssue = Data.define(
    :title,
    :details,
    :severity,
    :confidence,
    :tags,
    :affected_lines
  ) do
    def initialize(title:, severity:, confidence:, details: nil, tags: [], affected_lines: [])
      super
    end
  end

  # Normalized issue enriched with file context and an assigned ID.
  class Issue
    attr_accessor :id
    attr_reader :file, :title, :details, :severity, :confidence, :tags, :affected_lines

    def self.from_hash(hash)
      hash = hash.transform_keys(&:to_s)
      ranges = parse_affected_lines(hash['affected_lines'])
      build_from_hash(hash, ranges)
    end

    def self.parse_affected_lines(lines)
      Array(lines).map do |line|
        line = line.transform_keys(&:to_s) if line.respond_to?(:transform_keys)
        AffectedRange.new(
          start_line: line['start_line'],
          end_line: line['end_line'] || line['start_line'],
          proposal: line['proposal']
        )
      end
    end

    def self.build_from_hash(hash, affected_lines)
      raw = RawIssue.new(
        title: hash.fetch('title'),
        severity: hash.fetch('severity'),
        confidence: hash.fetch('confidence'),
        details: hash['details'],
        tags: hash['tags'] || [],
        affected_lines: affected_lines
      )
      new(id: hash['id'], file: hash['file'], raw_issue: raw, affected_lines: affected_lines)
    end

    def initialize(id:, file:, raw_issue:, affected_lines:)
      @id = id
      @file = file
      @title = raw_issue.title
      @details = raw_issue.details
      @severity = raw_issue.severity
      @confidence = raw_issue.confidence
      @tags = raw_issue.tags || []
      @affected_lines = affected_lines
    end

    def to_h
      {
        'id' => @id,
        'file' => @file,
        'title' => @title,
        'details' => @details,
        'severity' => @severity,
        'confidence' => @confidence,
        'tags' => @tags,
        'affected_lines' => @affected_lines.map { |range| range.to_h.transform_keys(&:to_s) }
      }
    end
  end

  # Collection of issues and metadata produced by a review run.
  class Report
    attr_reader :target, :summary, :issues, :processing_warnings, :created_at, :model,
                :number_of_processed_files

    def self.from_file(path)
      data = JSON.parse(File.read(path))
      from_hash(data)
    end

    def self.target_from_hash(data)
      target_data = (data['target'] || {}).transform_keys(&:to_s)
      ReviewTarget.new(**ReviewTarget.members.to_h { |m| [m, target_data[m.to_s]] })
    end

    def self.from_hash(data)
      target = target_from_hash(data)
      issues = Array(data['issues']).map { |issue| Issue.from_hash(issue) }
      new(
        target: target,
        model: data['model'],
        summary: data['summary'],
        issues: issues,
        processing_warnings: data['processing_warnings'] || [],
        number_of_processed_files: data['number_of_processed_files']
      )
    end

    def initialize(target:, model:, summary: nil, issues: [], processing_warnings: [],
                   number_of_processed_files: nil)
      @target = target
      @model = model
      @summary = summary
      @issues = Array(issues)
      @processing_warnings = Array(processing_warnings)
      @number_of_processed_files = number_of_processed_files || @issues.map(&:file).uniq.size
      @created_at = Time.now.iso8601
    end

    def total_issues
      @issues.size
    end

    def to_h
      {
        'target' => @target.to_h.transform_keys(&:to_s),
        'model' => @model,
        'summary' => @summary,
        'issues' => @issues.map(&:to_h),
        'number_of_processed_files' => number_of_processed_files,
        'total_issues' => total_issues,
        'processing_warnings' => @processing_warnings,
        'created_at' => @created_at
      }
    end

    def save(output_dir)
      FileUtils.mkdir_p(output_dir)
      File.write(File.join(output_dir, 'code-review-report.json'), JSON.pretty_generate(to_h))
    end
  end
end
