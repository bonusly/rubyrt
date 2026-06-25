# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Rubyrt::Verifier do
  subject(:verifier) do
    described_class.new(
      config: config,
      changeset: fake_changeset,
      prompt_builder: Rubyrt::PromptBuilder.new(Rubyrt::Configuration.new(root: tmp_dir)),
      llm_client: fake_llm_client
    )
  end

  let(:tmp_dir) { Dir.mktmpdir }
  let(:config) { { 'verify' => { 'enabled' => true }, 'max_concurrent_tasks' => 4 } }
  let(:fake_changeset) do
    instance_double(Rubyrt::Changeset, diff_text_for: "+ x\n", full_content_for: "x\n")
  end
  let(:issues) { [issue('keep-me'), issue('reject-me')] }
  # Branch on the rendered prompt (which embeds the finding title) so the result
  # is independent of fiber scheduling order.
  let(:fake_llm_client) do
    instance_double(Rubyrt::LlmClient).tap do |client|
      allow(client).to receive(:complete_with_schema) do |prompt, *_|
        verdict(prompt.include?('reject-me') ? 'reject' : 'uphold')
      end
    end
  end

  def issue(title)
    Rubyrt::Issue.from_hash('title' => title, 'details' => 'd', 'severity' => 1,
                            'confidence' => 1, 'tags' => [], 'file' => 'app.rb',
                            'affected_lines' => [{ 'start_line' => 1 }])
  end

  def verdict(value)
    instance_double(RubyLLM::Message, content: { 'verdict' => value, 'reasoning' => 'r' })
  end

  after { FileUtils.rm_rf(tmp_dir) }

  it 'drops findings the critic rejects and keeps the rest' do
    kept = verifier.call(issues)
    expect(kept.map(&:title)).to eq(['keep-me'])
  end

  it 'returns issues untouched without calling the LLM when disabled', :aggregate_failures do
    config['verify']['enabled'] = false
    expect(verifier.call(issues)).to eq(issues)
    expect(fake_llm_client).not_to have_received(:complete_with_schema)
  end

  it 'short-circuits on an empty list' do
    expect(verifier.call([])).to eq([])
  end

  context 'when the critic call fails' do
    let(:fake_llm_client) do
      instance_double(Rubyrt::LlmClient).tap do |client|
        allow(client).to receive(:complete_with_schema).and_raise(StandardError, 'boom')
      end
    end

    it 'fails open: keeps the finding and records a warning', :aggregate_failures do
      kept = verifier.call([issue('keep-me')])
      expect(kept.map(&:title)).to eq(['keep-me'])
      expect(verifier.warnings).to include(/Could not verify finding 'keep-me'.*boom/)
    end
  end
end
