# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Rubyrt::Lsp::Client do
  subject(:client) { described_class.new(command: ['ruby', fake_server], root: tmp_dir) }

  let(:tmp_dir) { Dir.mktmpdir }
  # A minimal stand-in LSP server: speaks Content-Length framed JSON-RPC,
  # responds to initialize and workspace/symbol. Exercises our framing and id
  # correlation without depending on a real language server.
  let(:fake_server) do
    path = File.join(tmp_dir, 'fake_lsp.rb')
    File.write(path, <<~RUBY)
      $stdin.binmode
      $stdout.binmode
      def read_message
        len = nil
        while (line = $stdin.gets)
          line = line.strip
          break if line.empty?
          len = $1.to_i if line =~ /Content-Length:\\s*(\\d+)/i
        end
        len && JSON.parse($stdin.read(len))
      end
      def send_msg(obj)
        body = JSON.generate(obj)
        $stdout.write("Content-Length: \#{body.bytesize}\\r\\n\\r\\n\#{body}")
        $stdout.flush
      end
      require 'json'
      loop do
        msg = read_message or break
        case msg['method']
        when 'initialize' then send_msg(jsonrpc: '2.0', id: msg['id'], result: { capabilities: {} })
        when 'initialized' # signal "indexing done" so the readiness wait returns at once
          send_msg(jsonrpc: '2.0', method: '$/progress', params: { value: { kind: 'end' } })
        when 'workspace/symbol'
          send_msg(jsonrpc: '2.0', id: msg['id'], result: [
            { 'name' => msg.dig('params', 'query'),
              'location' => { 'uri' => 'file:///x.rb', 'range' => { 'start' => { 'line' => 0 } } } }
          ])
        when 'textDocument/didOpen'
          uri = msg.dig('params', 'textDocument', 'uri')
          send_msg(jsonrpc: '2.0', method: 'textDocument/publishDiagnostics', params: {
                     uri: uri,
                     diagnostics: [{ 'code' => 'Fake/Cop', 'message' => 'Fake/Cop: bad',
                                     'severity' => 2, 'range' => { 'start' => { 'line' => 3 } } }]
                   })
        when 'shutdown' then send_msg(jsonrpc: '2.0', id: msg['id'], result: nil)
        when 'exit' then break
        end
      end
    RUBY
    path
  end

  after { FileUtils.rm_rf(tmp_dir) }

  it 'initializes and returns workspace/symbol results' do # rubocop:disable RSpec/ExampleLength
    results = client.lookup('Widget')
    expect(results).to eq([
                            { 'name' => 'Widget',
                              'location' => { 'uri' => 'file:///x.rb', 'range' => { 'start' => { 'line' => 0 } } } }
                          ])
  ensure
    client.shutdown
  end

  it 'opens a document and returns the pushed diagnostics' do
    diagnostics = client.diagnostics(uri: 'file:///a.rb', text: "x=1\n")
    expect(diagnostics).to eq([{ 'code' => 'Fake/Cop', 'message' => 'Fake/Cop: bad',
                                 'severity' => 2, 'range' => { 'start' => { 'line' => 3 } } }])
  ensure
    client.shutdown
  end

  it 'raises LspError when the command does not exist' do
    bad = described_class.new(command: ['definitely-not-a-real-lsp-binary'], root: tmp_dir)
    expect { bad.lookup('x') }.to raise_error(Rubyrt::LspError, /not found/)
  end
end
