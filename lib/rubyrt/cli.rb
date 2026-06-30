# frozen_string_literal: true

require 'thor'
require 'fileutils'
require 'rubyrt'
require 'rubyrt/version'

module Rubyrt
  # Thor-based CLI for rubyrt. Mirrors the command structure of Gito where possible:
  # review, report, files, github-comment, setup.
  # rubocop:disable Metrics/ClassLength
  class CLI < Thor
    class_option :debug, type: :boolean, default: false,
                         desc: 'Enable debug logging (also: RUBYRT_DEBUG env var)'

    desc 'version', 'Show rubyrt version'
    def version
      puts Rubyrt::VERSION
    end

    # Override the default help output to also list each command's options,
    # so `rubyrt --help` shows what flags each command accepts.
    def help(command = nil, subcommand = false) # rubocop:disable Style/OptionalBooleanParameter
      return super if command

      shell.say 'Commands:'
      self.class.commands.reject { |_, c| c.hidden? }.sort.each do |name, cmd|
        print_command_help(name, cmd)
      end
    end

    no_commands do
      def print_command_help(name, cmd)
        shell.say "  #{name}"
        shell.say "    #{cmd.description}" if cmd.description && !cmd.description.empty?
        print_command_options(cmd)
      end

      def print_command_options(cmd)
        opts = cmd.options.values
        return if opts.empty?

        opts.each { |opt| shell.say option_line(opt) }
      end

      def option_line(opt)
        switches = ["--#{opt.name.tr('_', '-')}"]
        switches.concat(Array(opt.aliases).map(&:to_s))
        line = "    #{switches.join(', ').ljust(28)}# #{opt.description}"
        return line if opt.default.nil?

        "#{line} (Default: #{opt.default.inspect})"
      end
    end

    desc 'review', 'Perform a code review of the target codebase changes'
    option :what, type: :string, aliases: '-w', desc: 'Git ref to review'
    option :against, type: :string, aliases: '-v', desc: 'Git ref to compare against'
    option :filters, type: :string, aliases: '-f', desc: 'Filter reviewed files by glob pattern(s)'
    option :merge_base, type: :boolean, default: true, desc: 'Use merge base for comparison'
    option :output, type: :string, aliases: '-o', desc: 'Output folder for the review report'
    option :all, type: :boolean, default: false, desc: 'Review whole codebase'
    option :model, type: :string, aliases: '-m', desc: 'LLM model to use for the review'
    option :provider, type: :string, aliases: '-p', desc: 'LLM provider to use (e.g. openai, anthropic)'
    def review(*)
      # Thor passes positional args we don't use; accept and ignore them.
      config = Rubyrt::Configuration.new(overrides: { model: options[:model], provider: options[:provider] }.compact)
      changeset = build_changeset(config)
      clients = build_lsp_clients(config, changeset)
      tools = clients.map { |client| Rubyrt::Lsp::SymbolTool.new(client: client, root: changeset.workdir) }
      tools << Rubyrt::FileTool.new(root: changeset.workdir)
      report = build_reviewer(config, changeset, tools).review
      render_report(report, config)
    rescue StandardError => e
      warn "Review failed: #{e.class}: #{e.message}"
      warn e.backtrace&.first(5)&.join("\n") if debug_enabled?
      exit 1
    ensure
      clients&.each(&:shutdown)
    end

    desc 'files', 'List files in the changeset'
    option :what, type: :string, aliases: '-w', desc: 'Git ref to review'
    option :against, type: :string, aliases: '-v', desc: 'Git ref to compare against'
    option :filters, type: :string, aliases: '-f', desc: 'Filter reviewed files by glob pattern(s)'
    option :merge_base, type: :boolean, default: true, desc: 'Use merge base for comparison'
    option :all, type: :boolean, default: false, desc: 'List all tracked files'
    option :diff, type: :boolean, default: false, desc: 'Show diff content'
    def files
      changeset = build_changeset
      changeset.files.each { |file| print_file(file, changeset) }
    rescue StandardError => e
      warn "Could not list files: #{e.class}: #{e.message}"
      exit 1
    end

    desc 'report', 'Render a saved code review report'
    option :source, type: :string, aliases: '-s', desc: 'Source JSON report to load'
    option :format, type: :string, default: 'cli', desc: 'Output format (cli, md)'
    def report
      source = options[:source] || 'code-review-report.json'
      report = Rubyrt::Report.from_file(source)
      renderer = Rubyrt::ReportRenderer.new(report, severity_scale: config_for_report.severity_scale)
      puts options[:format] == 'md' ? renderer.to_md : renderer.to_cli
    rescue StandardError => e
      warn "Could not render report: #{e.message}"
      exit 1
    end

    desc 'github-comment', 'Post a code review comment to GitHub'
    option :md_report_file, type: :string, desc: 'Path to the Markdown report'
    option :pr, type: :numeric, desc: 'Pull Request number'
    option :gh_repo, type: :string, desc: 'owner/repo'
    option :token, type: :string, desc: 'GitHub token'
    option :resolve_token, type: :string,
                           desc: 'Token for resolving review threads (PAT/App; GITHUB_TOKEN cannot)'
    def github_comment
      context = resolve_github_context
      commenter = build_commenter(context)
      summary = File.read(options[:md_report_file] || 'code-review-report.md')
      report = Rubyrt::Report.from_file(json_path_for(options[:md_report_file]))
      debug_approve_state
      commenter.post_review(summary: summary, report: report)
      maybe_approve(context, report)
    rescue StandardError => e
      warn "GitHub comment failed: #{e.message}"
      exit 1
    end

    desc 'models', 'Refresh and save the local RubyLLM models registry'
    option :path, type: :string, aliases: '-p',
                  desc: 'Where to save the models JSON (defaults to the models_file config)'
    def models
      config = Rubyrt::Configuration.new
      expanded = resolve_models_path(config)
      FileUtils.mkdir_p(File.dirname(expanded))

      # Point the registry at the target so save_to_json writes there, and so
      # refresh is consistent with the file reviews will load. Apply provider
      # credentials to the global config so refresh can fetch provider model
      # lists in addition to the public models.dev catalog.
      RubyLLM.config.model_registry_file = expanded
      Rubyrt::LlmClient.apply_provider_config!(RubyLLM.config, config)

      puts 'Refreshing models from configured providers and models.dev...'
      RubyLLM.models.refresh!
      RubyLLM.models.save_to_json(expanded)
      puts "Saved #{RubyLLM.models.count} models to #{expanded}"
    rescue StandardError => e
      warn "Models refresh failed: #{e.class}: #{e.message}"
      warn e.backtrace&.first(5)&.join("\n") if debug_enabled?
      exit 1
    end

    # rubocop:disable Metrics/BlockLength
    no_commands do
      # Resolves the local models JSON path from --path or the models_file
      # config. Exits with a usage message when neither is set.
      def resolve_models_path(config)
        path = options[:path] || config['models_file']
        unless path && !path.to_s.strip.empty?
          warn 'No models_file configured. Set models_file in .rubyrt/config.toml or pass --path.'
          exit 1
        end
        File.expand_path(path)
      end

      def build_changeset(config = Rubyrt::Configuration.new)
        Rubyrt::Changeset.new(
          head_ref: options[:what],
          base_ref: options[:against],
          all: options[:all] || false,
          filters: options[:filters]&.split(','),
          exclude_files: config['exclude_files'],
          # Thor's options hash isn't indifferent for #fetch, so read via [] (it
          # always has a value because the option declares default: true).
          merge_base: options[:merge_base]
        )
      end

      # `report` command has no config overrides of its own; load defaults so
      # the severity scale matches what was used at review time.
      def config_for_report
        Rubyrt::Configuration.new
      end

      def build_reviewer(config, changeset, tools = [])
        Rubyrt::Reviewer.new(
          config: config,
          changeset: changeset,
          prompt_builder: Rubyrt::PromptBuilder.new(config),
          llm_client: Rubyrt::LlmClient.new(config),
          tools: tools,
          debug: debug_enabled?
        )
      end

      # One LSP client per configured language whose extensions match a changed
      # file, so we don't spawn a server the review won't use.
      def build_lsp_clients(config, changeset)
        servers = config['lsp']
        return [] unless servers.is_a?(Hash) && !servers.empty?

        changed_exts = changeset.files.map { |f| File.extname(f) }
        servers.values.filter_map do |server|
          next unless Array(server['extensions']).intersect?(changed_exts)

          Rubyrt::Lsp::Client.new(command: server['command'], root: changeset.workdir)
        end
      end

      def render_report(report, config)
        output = options[:output] || '.'
        renderer = Rubyrt::ReportRenderer.new(report, severity_scale: config.severity_scale)
        report.save(output)
        File.write(File.join(output, 'code-review-report.md'), renderer.to_md)
        puts renderer.to_cli
      end

      def print_file(file, changeset)
        if options[:diff]
          puts "--- #{file} ---"
          puts changeset.diff_text_for(file)
        else
          puts file
        end
      end

      def repo_owner(context)
        options[:gh_repo]&.split('/')&.first || context&.owner
      end

      def repo_name(context)
        options[:gh_repo]&.split('/')&.last || context&.repo_name
      end

      def json_path_for(md_path)
        return 'code-review-report.json' unless md_path

        ext = File.extname(md_path)
        ext.empty? ? "#{md_path}.json" : md_path.sub(/#{Regexp.escape(ext)}\z/, '.json')
      end

      # Only read the GitHub Actions environment when the caller hasn't supplied
      # the repo and PR explicitly, so manual/local runs aren't forced through it.
      def resolve_github_context
        return nil if options[:gh_repo] && options[:pr]

        Rubyrt::GitHub::Context.from_env
      end

      def build_commenter(context)
        Rubyrt::GitHub::Commenter.new(
          token: options[:token] || ENV.fetch('GITHUB_TOKEN', nil),
          resolve_token: options[:resolve_token] || ENV.fetch('RUBYRT_RESOLVE_TOKEN', nil),
          owner: repo_owner(context),
          repo: repo_name(context),
          pr_number: options[:pr] || context&.pr_number
        )
      end

      # Auto-approve the PR when the [approve] config block is enabled. Loads
      # config here because github-comment otherwise runs without it.
      def maybe_approve(context, report)
        approve = Rubyrt::Configuration.new['approve']
        return unless approve.is_a?(Hash) && approve['enabled']

        build_approver(context, approve).run(report)
      end

      def build_approver(context, approve_config)
        Rubyrt::GitHub::Approver.new(
          token: options[:token] || ENV.fetch('GITHUB_TOKEN', nil),
          resolve_token: options[:resolve_token] || ENV.fetch('RUBYRT_RESOLVE_TOKEN', nil),
          owner: repo_owner(context),
          repo: repo_name(context),
          pr_number: options[:pr] || context&.pr_number,
          config: approve_config
        )
      end

      # Debug is on when --debug is passed OR RUBYRT_DEBUG is set to a non-empty,
      # non-false value. Empty string is treated as off so GitHub Actions' default
      # empty-variable expansion doesn't accidentally enable debug on every run.
      def debug_enabled?
        env_val = ENV.fetch('RUBYRT_DEBUG', nil)
        env_on = env_val && !env_val.strip.empty? && !%w[0 false].include?(env_val.strip.downcase)
        env_on || options[:debug]
      end

      # Mirror maybe_approve's config load so the debug banner reports the same
      # approve state that will actually be evaluated.
      def debug_approve_state
        return unless debug_enabled?

        approve = Rubyrt::Configuration.new['approve']
        enabled = approve.is_a?(Hash) ? approve['enabled'] : false
        warn "[DEBUG] Approve enabled: #{enabled ? 'yes' : 'no'}"
      end
    end
    # rubocop:enable Metrics/BlockLength
    # rubocop:enable Metrics/ClassLength
  end
end
