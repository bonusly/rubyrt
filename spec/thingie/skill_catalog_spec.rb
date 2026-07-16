# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Thingie::SkillCatalog do
  let(:tmp_dir) { Dir.mktmpdir }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe '.tool' do
    it 'returns nil when there are no skills and no aux files' do
      config = Thingie::Configuration.new(root: tmp_dir, overrides: { skill_directories: [] })
      expect(described_class.tool(config)).to be_nil
    end

    context 'with skill fragments' do
      before do
        FileUtils.mkdir_p(File.join(tmp_dir, '.cursor'))
        File.write(File.join(tmp_dir, '.cursor', 'rails.md'), "# Rails rules\nAlways use strong params.")
      end

      it 'returns a SkillTool whose description lists the skill without its full body', :aggregate_failures do
        tool = described_class.tool(Thingie::Configuration.new(root: tmp_dir))

        expect(tool).to be_a(RubyLLM::Skills::SkillTool)
        expect(tool.description).to include('.cursor/rails')
        expect(tool.description).to include('Rails rules')
        expect(tool.description).not_to include('Always use strong params.')
      end

      it 'loads the full skill content on demand' do
        tool = described_class.tool(Thingie::Configuration.new(root: tmp_dir))
        expect(tool.execute(command: '.cursor/rails')).to include('Always use strong params.')
      end
    end

    context 'with same-named skills across directories' do
      before do
        %w[.agents .cursor].each do |dir|
          FileUtils.mkdir_p(File.join(tmp_dir, dir))
          File.write(File.join(tmp_dir, dir, 'rails_rules.md'), "#{dir} content")
        end
      end

      it 'namespaces skill names by source directory so both remain findable', :aggregate_failures do
        catalog = described_class.new(Thingie::Configuration.new(root: tmp_dir))

        expect(catalog.list.map(&:name)).to contain_exactly('.agents/rails_rules', '.cursor/rails_rules')
        expect(catalog.find('.agents/rails_rules').content).to eq('.agents content')
        expect(catalog.find('.cursor/rails_rules').content).to eq('.cursor content')
      end
    end

    context 'with aux_files configured' do
      let(:config) do
        Thingie::Configuration.new(
          root: tmp_dir,
          overrides: { skill_directories: [], aux_files: ['docs/conventions.md', 'docs/missing.md'] }
        )
      end

      before do
        FileUtils.mkdir_p(File.join(tmp_dir, 'docs'))
        File.write(File.join(tmp_dir, 'docs', 'conventions.md'), 'Use frozen_string_literal.')
      end

      it 'registers an existing aux file as a findable skill', :aggregate_failures do
        catalog = described_class.new(config)
        skill = catalog.find('docs/conventions.md')

        expect(skill).not_to be_nil
        expect(skill.description).to eq('Auxiliary reference file: docs/conventions.md')
        expect(skill.content).to eq('Use frozen_string_literal.')
      end

      it 'omits a configured but missing aux file' do
        catalog = described_class.new(config)
        expect(catalog.list.map(&:name)).not_to include('docs/missing.md')
      end
    end
  end
end
