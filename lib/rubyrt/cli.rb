# frozen_string_literal: true

require 'thor'
require 'rubyrt'
require 'rubyrt/version'

module Rubyrt
  # Thor-based CLI for rubyrt. Mirrors the command structure of Gito where possible:
  # review, report, files, github-comment, setup.
  class CLI < Thor
    desc 'version', 'Show rubyrt version'
    def version
      puts Rubyrt::VERSION
    end

    desc 'review', 'Perform a code review of the target codebase changes'
    option :what, type: :string, aliases: '-w', desc: 'Git ref to review'
    option :against, type: :string, aliases: '-v', desc: 'Git ref to compare against'
    option :filters, type: :string, aliases: '-f', desc: 'Filter reviewed files by glob pattern(s)'
    option :merge_base, type: :boolean, default: true, desc: 'Use merge base for comparison'
    option :output, type: :string, aliases: '-o', desc: 'Output folder for the review report'
    option :all, type: :boolean, default: false, desc: 'Review whole codebase'
    def review
      config = Rubyrt::Configuration.new
      changeset = build_changeset
      report = build_reviewer(config, changeset).review
      render_report(report)
    rescue StandardError => e
      warn "Review failed: #{e.message}"
      exit 1
    end

    desc 'files', 'List files in the changeset'
    option :what, type: :string, aliases: '-w', desc: 'Git ref to review'
    option :against, type: :string, aliases: '-v', desc: 'Git ref to compare against'
    option :filters, type: :string, aliases: '-f', desc: 'Filter reviewed files by glob pattern(s)'
    option :merge_base, type: :boolean, default: true, desc: 'Use merge base for comparison'
    option :diff, type: :boolean, default: false, desc: 'Show diff content'
    def files
      build_changeset.files.each { |file| print_file(file) }
    end

    desc 'report', 'Render a saved code review report'
    option :source, type: :string, aliases: '-s', desc: 'Source JSON report to load'
    option :format, type: :string, default: 'cli', desc: 'Output format (cli, md)'
    def report
      source = options[:source] || 'code-review-report.json'
      report = Rubyrt::Report.from_file(source)
      renderer = Rubyrt::ReportRenderer.new(report)
      puts options[:format] == 'md' ? renderer.to_md : renderer.to_cli
    end

    # rubocop:disable Metrics/BlockLength
    no_commands do
      def build_changeset
        Rubyrt::Changeset.new(
          head_ref: options[:what],
          base_ref: options[:against]
        )
      end

      def build_reviewer(config, changeset)
        Rubyrt::Reviewer.new(
          config: config,
          changeset: changeset,
          prompt_builder: Rubyrt::PromptBuilder.new(config),
          llm_client: Rubyrt::LlmClient.new(config),
          adapters: [Rubyrt::Adapters::RuboCopAdapter.new(config: config)]
        )
      end

      def render_report(report)
        report.save(options[:output] || '.')
        puts Rubyrt::ReportRenderer.new(report).to_md
      end

      def print_file(file)
        if options[:diff]
          puts "--- #{file} ---"
          puts build_changeset.diff_text_for(file)
        else
          puts file
        end
      end
    end
    # rubocop:enable Metrics/BlockLength
  end
end
