# frozen_string_literal: true

# RubyRT namespace module. CLI, configuration, review engine, and reporters
# live under Rubyrt::.
module Rubyrt
end

require_relative 'rubyrt/version'
require_relative 'rubyrt/configuration'
require_relative 'rubyrt/prompt_builder'
require_relative 'rubyrt/models'
require_relative 'rubyrt/changeset'
require_relative 'rubyrt/issue_id_generator'
require_relative 'rubyrt/issue_parser'
require_relative 'rubyrt/code_enricher'
require_relative 'rubyrt/post_processor'
require_relative 'rubyrt/llm_client'
require_relative 'rubyrt/report_renderer'
require_relative 'rubyrt/adapters/rubocop_adapter'
require_relative 'rubyrt/reviewer'
require_relative 'rubyrt/github'
