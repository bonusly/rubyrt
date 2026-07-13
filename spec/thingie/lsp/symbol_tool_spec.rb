# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Thingie::Lsp::SymbolTool do
  subject(:tool) { described_class.new(client: client, root: tmp_dir) }

  let(:tmp_dir) { Dir.mktmpdir }
  let(:file_path) { File.join(tmp_dir, 'lib', 'thing.rb') }
  let(:client) { instance_double(Thingie::Lsp::Client) }

  before do
    FileUtils.mkdir_p(File.dirname(file_path))
    File.write(file_path, "module Outer\n  def thing\n    42\n  end\nend\n")
  end

  after { FileUtils.rm_rf(tmp_dir) }

  def symbol(start_line, end_line)
    {
      'name' => 'thing',
      'location' => {
        'uri' => "file://#{file_path}",
        'range' => { 'start' => { 'line' => start_line }, 'end' => { 'line' => end_line } }
      }
    }
  end

  it 'returns the sliced definition source with a relative path', :aggregate_failures do
    allow(client).to receive(:lookup).with('thing').and_return([symbol(1, 3)])

    result = tool.execute(query: 'thing')

    expect(result).to include('lib/thing.rb:2') # 0-indexed line 1 => display line 2
    expect(result).to include("  def thing\n    42\n  end")
    expect(result).not_to include('module Outer') # outside the range
  end

  it 'reports when nothing is found' do
    allow(client).to receive(:lookup).and_return([])

    expect(tool.execute(query: 'missing')).to eq('No definition found for `missing`.')
  end

  it 'degrades gracefully when the client raises' do
    allow(client).to receive(:lookup).and_raise(Thingie::LspError, 'boom')

    expect(tool.execute(query: 'thing')).to eq('Symbol lookup unavailable for `thing`: boom')
  end

  it 'caps the number of results' do
    allow(client).to receive(:lookup).and_return(Array.new(10) { symbol(1, 3) })

    expect(tool.execute(query: 'thing').scan('lib/thing.rb').size).to eq(described_class::MAX_RESULTS)
  end
end
