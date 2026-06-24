# frozen_string_literal: true

require 'tomlrb'
require 'dotenv'

module Rubyrt
  # Loads and merges RubyRT configuration.
  #
  # Layers (later layers override earlier ones):
  # 1. Bundled defaults from lib/rubyrt/config/default.toml
  # 2. Project-specific .rubyrt/config.toml
  # 3. ~/.rubyrt/.env (loaded into ENV via dotenv)
  # 4. OS environment variables
  # 5. Explicit overrides passed to Configuration.new
  class Configuration
    attr_reader :data, :root

    # Expanded lazily in load_user_env_file so a missing/unresolvable home
    # directory can't crash at load time.
    USER_ENV_FILE = '~/.rubyrt/.env'

    DEFAULT_SKILL_DIRECTORIES = %w[.agents .claude .cursor].freeze

    ENV_OVERRIDES = {
      'model' => 'LLM_MODEL',
      'provider' => 'LLM_PROVIDER',
      'llm_api_key' => 'LLM_API_KEY',
      'llm_api_base' => 'LLM_API_BASE',
      'github_token' => 'GITHUB_TOKEN',
      'log_file' => 'RUBYRT_LOG_FILE',
      'log_level' => 'RUBYRT_LOG_LEVEL'
    }.freeze

    INTEGER_ENV_OVERRIDES = {
      'retries' => 'LLM_RETRIES',
      'request_timeout' => 'LLM_REQUEST_TIMEOUT',
      'max_concurrent_tasks' => 'MAX_CONCURRENT_TASKS'
    }.freeze

    def initialize(root: Dir.pwd, overrides: {})
      @root = root
      @overrides = overrides.transform_keys(&:to_s)
      @data = build_data
    end

    def [](key)
      @data[key.to_s]
    end

    def dig(*keys)
      @data.dig(*keys.map(&:to_s))
    end

    def prompt_vars
      @data.fetch('prompt_vars', {})
    end

    def severity_scale
      @data.fetch('severity_scale', {})
    end

    def confidence_scale
      @data.fetch('confidence_scale', {})
    end

    def skill_directories
      # expand_path leaves absolute paths intact and resolves relative ones
      # against the project root.
      Array(@data.fetch('skill_directories', DEFAULT_SKILL_DIRECTORIES)).map { |d| File.expand_path(d, @root) }
    end

    def aux_files
      Array(@data.fetch('aux_files', [])).map { |path| File.expand_path(path, @root) }
    end

    def skills
      @skills ||= skill_directories.flat_map { |dir| load_skills_from(dir) }
    end

    private

    def build_data
      load_user_env_file
      defaults = load_toml(default_config_path)
      project = project_config_path ? load_toml(project_config_path) : {}

      apply_string_overrides(
        apply_env_overrides(deep_merge(defaults, project)),
        @overrides
      )
    end

    def load_user_env_file
      # File.expand_path('~/...') raises ArgumentError when HOME is unresolvable
      # (e.g. some containers); a missing user env file is not fatal.
      path = File.expand_path(USER_ENV_FILE)
      return unless File.file?(path)

      # Parse and assign explicitly so the user's file always overrides any
      # inherited ENV, without relying on a particular Dotenv overwrite API.
      Dotenv.parse(path).each { |key, value| ENV[key] = value }
    rescue StandardError
      # A missing/unreadable/malformed user env file must never be fatal.
      nil
    end

    def default_config_path
      File.expand_path('config/default.toml', __dir__)
    end

    def project_config_path
      path = File.join(@root, '.rubyrt', 'config.toml')
      File.file?(path) ? path : nil
    end

    def load_toml(path)
      Tomlrb.load_file(path, symbolize_keys: false)
    rescue StandardError => e
      raise "Failed to load config from #{path}: #{e.message}"
    end

    def deep_merge(base, override)
      base.each_with_object({}) do |(key, value), merged|
        merged[key] = merge_values(value, override[key])
      end.merge(override.slice(*override.keys - base.keys))
    end

    def merge_values(base_value, override_value)
      if base_value.is_a?(Hash) && override_value.is_a?(Hash)
        deep_merge(base_value, override_value)
      else
        override_value.nil? ? base_value : override_value
      end
    end

    def apply_env_overrides(config)
      config.merge(string_env_overrides).merge(integer_env_overrides(config))
    end

    def string_env_overrides
      ENV_OVERRIDES.transform_values do |env_key|
        ENV.fetch(env_key, nil)
      end.compact
    end

    def integer_env_overrides(config)
      result = {}
      INTEGER_ENV_OVERRIDES.each do |key, env_key|
        value = ENV.fetch(env_key, nil)
        # Treat a blank env var as unset so it doesn't coerce to 0.
        result[key] = value && !value.strip.empty? ? value.to_i : config[key]
      end
      result
    end

    def apply_string_overrides(config, overrides)
      config.merge(overrides)
    end

    def load_skills_from(dir)
      return [] unless Dir.exist?(dir)

      Dir.glob(File.join(dir, '**', '*.md')).map do |path|
        SkillFragment.new(path: path, content: File.read(path), source: dir)
      end
    end
  end

  # A single skill prompt fragment discovered from .agents, .claude, or .cursor.
  class SkillFragment
    attr_reader :path, :content, :source

    def initialize(path:, content:, source:)
      @path = path
      @content = content
      @source = source
    end

    def name
      File.basename(@path, '.md')
    end
  end
end
