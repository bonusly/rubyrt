# frozen_string_literal: true

# Top-level namespace for RubyRT. The CLI, configuration, review engine, and
# reporters all live under the Rubyrt module.
module Rubyrt
end

require_relative 'rubyrt/errors'
require_relative 'rubyrt/version'
require_relative 'rubyrt/configuration'
require_relative 'rubyrt/prompt_builder'
require_relative 'rubyrt/models'
require_relative 'rubyrt/changeset'
require_relative 'rubyrt/issue_parser'
require_relative 'rubyrt/schemas/issue_schema'
require_relative 'rubyrt/schemas/verdict_schema'
require_relative 'rubyrt/code_enricher'
require_relative 'rubyrt/post_processor'
require_relative 'rubyrt/debug_output'
require_relative 'rubyrt/llm_client'
require_relative 'rubyrt/verifier'
require_relative 'rubyrt/lsp/client'
require_relative 'rubyrt/lsp/symbol_tool'
require_relative 'rubyrt/file_tool'
require_relative 'rubyrt/report_renderer'
require_relative 'rubyrt/reviewer'
require_relative 'rubyrt/github'
