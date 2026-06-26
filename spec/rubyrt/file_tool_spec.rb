# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Rubyrt::FileTool do
  subject(:tool) { described_class.new(root: tmp_dir) }

  let(:tmp_dir) { Dir.mktmpdir }
  let(:text_path) { File.join(tmp_dir, 'lib', 'thing.rb') }
  let(:binary_path) { File.join(tmp_dir, 'assets', 'blob.bin') }

  before do
    FileUtils.mkdir_p(File.dirname(text_path))
    File.write(text_path, "module Outer\n  def thing\n    42\n  end\nend\n")
    FileUtils.mkdir_p(File.dirname(binary_path))
    File.binwrite(binary_path, "\x00\x01\x02binary\x00")
  end

  after { FileUtils.rm_rf(tmp_dir) }

  it 'returns the relative path and contents for an existing text file' do
    result = tool.execute(path: 'lib/thing.rb')

    expect(result).to include('lib/thing.rb')
    expect(result).to include("module Outer\n  def thing\n    42\n  end\nend")
  end

  it 'reports when the path does not exist' do
    expect(tool.execute(path: 'lib/missing.rb')).to eq('Path `lib/missing.rb` does not exist.')
  end

  it 'reports when the path is a directory' do
    expect(tool.execute(path: 'lib')).to eq('Path `lib` is a directory.')
  end

  it 'rejects paths that escape the working directory via ..' do
    expect(tool.execute(path: '../sibling.txt')).to eq('Path `../sibling.txt` is outside the working directory.')
  end

  it 'rejects paths that escape via a symlinked intermediate directory' do
    outside = Dir.mktmpdir
    secret = File.join(outside, 'secret.txt')
    File.write(secret, 'leaked')
    link = File.join(tmp_dir, 'link')
    File.symlink(outside, link)

    begin
      expect(tool.execute(path: 'link/secret.txt')).to eq('Path `link/secret.txt` is outside the working directory.')
    ensure
      FileUtils.rm_f(link)
      FileUtils.rm_rf(outside)
    end
  end

  it 'rejects a symlink whose target points outside the working directory' do
    outside = Dir.mktmpdir
    secret = File.join(outside, 'secret.txt')
    File.write(secret, 'leaked')
    link = File.join(tmp_dir, 'secret.lnk')
    File.symlink(secret, link)

    begin
      expect(tool.execute(path: 'secret.lnk')).to eq('Path `secret.lnk` is outside the working directory.')
    ensure
      FileUtils.rm_f(link)
      FileUtils.rm_rf(outside)
    end
  end

  it 'rejects absolute paths outside the working directory' do
    expect(tool.execute(path: '/etc/passwd')).to eq('Path `/etc/passwd` is outside the working directory.')
  end

  it 'declines to read binary files' do
    result = tool.execute(path: 'assets/blob.bin')

    expect(result).to include('binary file')
    expect(result).to include('assets/blob.bin')
    expect(result).not_to include("\x00") # never dumps binary bytes
  end

  it 'degrades gracefully on unexpected errors' do
    allow(File).to receive(:exist?).and_raise(Errno::EACCES, 'boom')

    expected = 'File lookup unavailable for `lib/thing.rb`: Permission denied - boom'
    expect(tool.execute(path: 'lib/thing.rb')).to eq(expected)
  end
end
