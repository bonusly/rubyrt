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
    attr_reader :data

    USER_ENV_FILE = File.expand_path('~/.rubyrt/.env').freeze

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

    def skill_directories
      %w[.agents .claude .cursor].map { |d| File.join(@root, d) }
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
      return unless File.file?(USER_ENV_FILE)

      Dotenv.load(USER_ENV_FILE, overwrite: true)
    end

    def default_config_path
      File.expand_path('config/default.toml', __dir__)
    end

    def project_config_path
      path = File.join(@root, '.rubyrt', 'config.toml')
      File.exist?(path) ? path : nil
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
      config.merge(
        'model' => ENV.fetch('LLM_MODEL', config['model']),
        'provider' => ENV.fetch('LLM_PROVIDER', config['provider']),
        'retries' => ENV.fetch('LLM_RETRIES', config['retries']).to_i,
        'max_concurrent_tasks' => ENV.fetch('MAX_CONCURRENT_TASKS',
                                            config['max_concurrent_tasks']).to_i,
        'github_token' => ENV.fetch('GITHUB_TOKEN', config['github_token']),
        'llm_api_key' => ENV.fetch('LLM_API_KEY', config['llm_api_key']),
        'llm_api_base' => ENV.fetch('LLM_API_BASE', config['llm_api_base'])
      )
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
