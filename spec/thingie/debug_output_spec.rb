# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Thingie::DebugOutput do
  subject(:debug_output) { described_class.new(config: config, changeset: changeset, enabled: true) }

  let(:config) { Thingie::Configuration.new(root: Dir.mktmpdir) }
  let(:changeset) { instance_double(Thingie::Changeset, files: ['app.rb']) }

  def response(input:, output:, context_window: nil)
    model_info = context_window ? instance_double(RubyLLM::Model::Info, context_window: context_window) : nil
    cost = instance_double(RubyLLM::Cost, total: 0.0001)
    instance_double(RubyLLM::Message, input_tokens: input, output_tokens: output, tool_calls: {},
                                      cache_read_tokens: nil, cache_write_tokens: nil, cost: cost,
                                      model_info: model_info)
  end

  describe '#review_call' do
    it 'includes context-window usage when the model info is available' do
      resp = response(input: 1000, output: 500, context_window: 10_000)

      expect do
        debug_output.review_call(file: 'app.rb', response: resp, issues_found: 0)
      end.to output(%r{1500/10000 ctx \(15\.0%\)}).to_stderr
    end

    it 'omits context-window usage when the model info is unavailable' do
      resp = response(input: 1000, output: 500)

      expect do
        debug_output.review_call(file: 'app.rb', response: resp, issues_found: 0)
      end.not_to output(/ctx/).to_stderr
    end
  end
end
