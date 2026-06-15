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
    option :output, type: :string, aliases: '-o', desc: 'Output folder for the code review report'
    option :all, type: :boolean, default: false, desc: 'Review whole codebase'
    def review
      raise NotImplementedError, 'review command is coming in a future commit'
    end

    desc 'files', 'List files in the changeset'
    option :what, type: :string, aliases: '-w', desc: 'Git ref to review'
    option :against, type: :string, aliases: '-v', desc: 'Git ref to compare against'
    option :filters, type: :string, aliases: '-f', desc: 'Filter reviewed files by glob pattern(s)'
    option :merge_base, type: :boolean, default: true, desc: 'Use merge base for comparison'
    option :diff, type: :boolean, default: false, desc: 'Show diff content'
    def files
      raise NotImplementedError, 'files command is coming in a future commit'
    end

    desc 'report', 'Render a saved code review report'
    option :source, type: :string, aliases: '-s', desc: 'Source JSON report to load'
    option :format, type: :string, default: 'cli', desc: 'Output format (cli, md)'
    def report
      raise NotImplementedError, 'report command is coming in a future commit'
    end

    desc 'github-comment', 'Post a code review comment to GitHub'
    option :md_report_file, type: :string, desc: 'Path to the Markdown report'
    option :pr, type: :numeric, desc: 'Pull Request number'
    option :gh_repo, type: :string, desc: 'owner/repo'
    option :token, type: :string, desc: 'GitHub token'
    def github_comment
      raise NotImplementedError, 'github-comment command is coming in a future commit'
    end

    desc 'setup', 'Configure rubyrt for local usage'
    def setup
      raise NotImplementedError, 'setup command is coming in a future commit'
    end
  end
end
