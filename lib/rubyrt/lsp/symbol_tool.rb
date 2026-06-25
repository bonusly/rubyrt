# frozen_string_literal: true

require 'ruby_llm'
require_relative '../errors'

module Rubyrt
  module Lsp
    # RubyLLM tool that lets the model fetch the definition of a class, module,
    # or method by name during a review, via a configured LSP client. Generic:
    # any LSP that implements workspace/symbol works here.
    class SymbolTool < RubyLLM::Tool
      MAX_RESULTS = 5
      # LSP SymbolKind values for local variables and instance/class fields. The
      # model asks about definitions (classes, methods, constants), so these rank
      # last — a fuzzy "User" query otherwise surfaces every `@user` assignment.
      VARIABLE_KINDS = [13, 8].freeze

      description <<~DESC
        Look up the definition of a class, module, or method by name to get more
        context about code referenced in the diff. Returns the source of matching
        definitions with their file paths. Query examples: "User", "User#save",
        "process_payment".
      DESC

      param :query, desc: 'Name of the class, module, or method to look up', required: true

      def initialize(client:, root:)
        super()
        @client = client
        @root = File.expand_path(root)
      end

      def execute(query:)
        term = base_name(query)
        symbols = rank(Array(@client.lookup(term)), term).first(MAX_RESULTS)
        return "No definition found for `#{query}`." if symbols.empty?

        symbols.map { |symbol| render(symbol) }.compact.join("\n\n")
      rescue LspError => e
        # Degrade gracefully: a context lookup failure must not fail the review.
        "Symbol lookup unavailable for `#{query}`: #{e.message}"
      end

      private

      # workspace/symbol matches on a simple name, so reduce "Foo::Bar#baz",
      # "Rubyrt::LlmClient", or "@user" to the bare identifier.
      def base_name(name)
        name.to_s.split(/::|#|\./).last.to_s.gsub(/\A[@$]+/, '')
      end

      # Exact name matches first, then definitions over variables/fields, so the
      # most relevant results survive the MAX_RESULTS cap.
      def rank(symbols, term)
        symbols.sort_by do |symbol|
          exact = base_name(symbol['name']).casecmp?(term) ? 0 : 1
          [exact, VARIABLE_KINDS.include?(symbol['kind']) ? 1 : 0]
        end
      end

      def render(symbol)
        location = symbol['location'] || {}
        path = path_from_uri(location['uri'])
        return nil unless path && File.file?(path)

        range = location['range'] || {}
        source = slice(path, range)
        "#{relative(path)}:#{line_number(range)}\n```\n#{source}\n```"
      end

      # LSP ranges are 0-indexed [start.line, end.line] inclusive of the lines
      # the definition spans.
      def slice(path, range)
        first = range.dig('start', 'line') || 0
        last = range.dig('end', 'line') || first
        File.readlines(path)[first..last].to_a.join.rstrip
      end

      def line_number(range)
        (range.dig('start', 'line') || 0) + 1
      end

      def path_from_uri(uri)
        return nil unless uri

        uri.delete_prefix('file://')
      end

      def relative(path)
        path.start_with?("#{@root}/") ? path.delete_prefix("#{@root}/") : path
      end
    end
  end
end
