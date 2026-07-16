# frozen_string_literal: true

require 'tomlrb'
require 'dotenv'

module Thingie
  # Loads and merges Thingie configuration.
  #
  # Layers (later layers override earlier ones):
  # 1. Bundled defaults from lib/thingie/config/default.toml
  # 2. Project-specific .thingie/config.toml
  # 3. ~/.thingie/.env (loaded into ENV via dotenv)
  # 4. OS environment variables
  # 5. Explicit overrides passed to Configuration.new
  class Configuration
    attr_reader :data, :root

    # Expanded lazily in load_user_env_file so a missing/unresolvable home
    # directory can't crash at load time.
    USER_ENV_FILE = '~/.thingie/.env'

    DEFAULT_SKILL_DIRECTORIES = %w[.agents .claude .cursor].freeze

    ENV_OVERRIDES = {
      'model' => 'LLM_MODEL',
      'provider' => 'LLM_PROVIDER',
      'llm_api_key' => 'LLM_API_KEY',
      'llm_api_base' => 'LLM_API_BASE',
      'github_token' => 'GITHUB_TOKEN',
      'log_file' => 'THINGIE_LOG_FILE',
      'log_level' => 'THINGIE_LOG_LEVEL',
      'models_file' => 'THINGIE_MODELS_FILE'
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

      apply_env_overrides(deep_merge(defaults, project)).merge(@overrides)
    end

    def load_user_env_file
      # File.expand_path('~/...') raises ArgumentError when HOME is unresolvable
      # (e.g. some containers); a missing user env file is not fatal.
      path = File.expand_path(USER_ENV_FILE)
      return unless File.file?(path)

      # Fill only unset keys so real OS environment variables (layer 4) keep
      # precedence over the user's ~/.thingie/.env defaults (layer 3).
      Dotenv.parse(path).each { |key, value| ENV[key] ||= value }
    rescue StandardError
      # A missing/unreadable/malformed user env file must never be fatal.
      nil
    end

    def default_config_path
      File.expand_path('config/default.toml', __dir__)
    end

    def project_config_path
      path = File.join(@root, '.thingie', 'config.toml')
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
      config.merge(string_env_overrides).merge(integer_env_overrides)
    end

    def string_env_overrides
      ENV_OVERRIDES.transform_values do |env_key|
        ENV.fetch(env_key, nil)
      end.compact
    end

    def integer_env_overrides
      # Only override keys that have a non-blank env var set; otherwise leave the
      # merged config value untouched (a blank var must not coerce to 0).
      INTEGER_ENV_OVERRIDES.each_with_object({}) do |(key, env_key), result|
        value = ENV.fetch(env_key, nil)
        result[key] = value.to_i if value && !value.strip.empty?
      end
    end

    def load_skills_from(dir)
      return [] unless Dir.exist?(dir)

      # Use base: so the directory name is taken literally — glob metacharacters
      # in the path (e.g. brackets) don't change which files are matched.
      Dir.glob('**/*.md', base: dir).map do |relative|
        path = File.join(dir, relative)
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

    # One-line summary used as progressive-disclosure metadata (SkillCatalog),
    # so the LLM sees this instead of the full skill body until it asks for it.
    def description
      line = content.each_line.map(&:strip).find { |l| !l.empty? } || name
      line = line.sub(/\A#+\s*/, '')
      line.length > 150 ? "#{line[0, 150].rstrip}…" : line
    end
  end
end
