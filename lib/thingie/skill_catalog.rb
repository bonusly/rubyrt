# frozen_string_literal: true

require 'ruby_llm/skills'

module Thingie
  # Adapts Thingie's own skill discovery (Configuration#skills) into a
  # RubyLLM::Skills loader, so their content is exposed to the LLM via
  # progressive disclosure (name + one-line description up front, full body
  # only on demand) instead of being inlined into every prompt for every file
  # in a review.
  class SkillCatalog < RubyLLM::Skills::Loader
    # Returns a RubyLLM::Skills::SkillTool for the catalog, or nil when there's
    # nothing to disclose (avoids registering a tool whose whole description
    # would be "No skills available.").
    def self.tool(config)
      catalog = new(config)
      return nil if catalog.list.empty?

      RubyLLM::Skills::SkillTool.new(catalog)
    end

    def initialize(config)
      super()
      @config = config
    end

    def list
      skills
    end

    protected

    def load_all
      skill_fragments
    end

    private

    def skill_fragments
      @config.skills.map do |fragment|
        build_skill(path: fragment.path, name: skill_name(fragment), description: fragment.description,
                    content: fragment.content)
      end
    end

    # Namespaced by source directory basename: multiple skill_directories can
    # discover files with the same basename (e.g. .agents/rails.md and
    # .cursor/rails.md), and skill names must be unique for SkillTool#find.
    def skill_name(fragment)
      "#{File.basename(fragment.source)}/#{fragment.name}"
    end

    def build_skill(path:, name:, description:, content:)
      RubyLLM::Skills::Skill.new(
        path: path,
        metadata: { 'name' => name, 'description' => description },
        content: content,
        virtual: true
      )
    end
  end
end
