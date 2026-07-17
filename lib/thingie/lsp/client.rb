# frozen_string_literal: true

require 'json'
require 'open3'
require 'timeout'
require 'io/wait' # IO#wait_readable
require_relative '../errors'

module Thingie
  module Lsp
    # Generic Language Server Protocol client: speaks JSON-RPC over the stdio of
    # a launched LSP process. Configured with a launch command and the workspace
    # root, so it works for any LSP (ruby-lsp, gopls, etc.) — only the command
    # changes. The transport (spawn, framing, initialize handshake, request/
    # notify, server-request acks) is generic; #lookup adds the one capability we
    # use today: workspace/symbol for code context.
    class Client # rubocop:disable Metrics/ClassLength
      INIT_TIMEOUT = 60 # ruby-lsp indexes the project at boot; allow time for it.
      REQUEST_TIMEOUT = 15
      # How long to wait for the server's first message before assuming it does
      # no background indexing (workspace/symbol is then usable immediately).
      READY_GRACE = 5

      # @param command [String, Array<String>] the LSP server launch command
      # @param root [String] the workspace root the server should index
      def initialize(command:, root:)
        @command = Array(command)
        @root = File.expand_path(root)
        # ponytail: global lock per client serializes lookups and blocks the
        # Async reactor during a call; fine at review throughput (a handful of
        # concurrent fibers). Move to async IO if it ever bottlenecks.
        @mutex = Mutex.new
        @id = 0
        @started = false
        @indexed = false
      end

      # Look up symbols by name. Returns an array of LSP SymbolInformation
      # hashes ({ "name", "kind", "location" => { "uri", "range" } }).
      #
      # @param query [String] the symbol name to search for
      # @return [Array<Hash>] matching SymbolInformation hashes
      def lookup(query)
        @mutex.synchronize do
          start unless @started
          ensure_indexed
          Array(request('workspace/symbol', { query: query }, timeout: REQUEST_TIMEOUT))
        end
      end

      # Gracefully shuts down the LSP server: sends `shutdown`/`exit`, then closes
      # the process. Safe to call when the server was never started.
      #
      # @return [void]
      def shutdown
        @mutex.synchronize do
          return unless @started

          request('shutdown', nil, timeout: 5)
          notify('exit')
        rescue StandardError
          # Best effort — we're tearing down regardless.
        ensure
          close
        end
      end

      private

      def start
        @stdin, @stdout, @stderr, @wait = Open3.popen3(*@command, chdir: @root)
        request('initialize', initialize_params, timeout: REQUEST_TIMEOUT)
        notify('initialized', {})
        # Mark started only after a successful handshake, so a failed init leaves
        # @started false (callers can retry) rather than trapped half-open.
        @started = true
      rescue Errno::ENOENT => e
        close
        raise LspError, "LSP command not found: #{@command.join(' ')} (#{e.message})"
      rescue StandardError
        close # don't leak the spawned process when init fails or times out
        raise
      end

      # workspace/symbol needs the project index; wait for it once, lazily, so
      # diagnostics-only servers (rubocop) never pay the indexing wait.
      def ensure_indexed
        return if @indexed

        wait_until_ready
        @indexed = true
      end

      # Servers that index in the background (e.g. ruby-lsp) report a work-done
      # progress sequence after `initialized`; workspace/symbol returns nothing
      # until it ends. Wait for that `end`, replying to any server requests along
      # the way. If no progress arrives within READY_GRACE, assume the server
      # needs no indexing and proceed.
      def wait_until_ready
        deadline = now + INIT_TIMEOUT
        saw_progress = false
        while (remaining = deadline - now).positive?
          # Until progress starts, only wait a short grace so a non-indexing
          # server isn't blocked for the full INIT_TIMEOUT.
          wait = saw_progress ? remaining : [remaining, READY_GRACE].min
          # wait_readable (not IO.select) so this yields to the Async scheduler.
          break unless @stdout.wait_readable(wait)

          message = read_message
          break if message.nil?

          answer_server_request(message)
          saw_progress ||= progress_kind(message) == 'begin'
          break if progress_kind(message) == 'end'
        end
      end

      def progress_kind(message)
        return nil unless message['method'] == '$/progress'

        message.dig('params', 'value', 'kind')
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def initialize_params
        {
          processId: Process.pid,
          rootUri: "file://#{@root}",
          capabilities: { workspace: { symbol: {} } }
        }
      end

      def request(method, params, timeout:)
        id = (@id += 1)
        write({ jsonrpc: '2.0', id: id, method: method, params: params })
        Timeout.timeout(timeout, LspError, "LSP request timed out: #{method}") do
          read_until_response(id)
        end
      end

      def notify(method, params = nil)
        write({ jsonrpc: '2.0', method: method, params: params })
      end

      # Read messages until we get the response matching `id`, ignoring server
      # notifications and requests (e.g. progress, log messages) along the way.
      def read_until_response(id)
        loop do
          message = read_message
          raise LspError, "LSP connection closed waiting for #{id}" if message.nil?

          answer_server_request(message)
          next unless message['id'] == id

          raise LspError, "LSP error: #{message['error']}" if message['error']

          return message['result']
        end
      end

      # A message carrying both an id and a method is a server→client request
      # (e.g. window/workDoneProgress/create). Acknowledge it so the server
      # doesn't stall; we don't need its result.
      def answer_server_request(message)
        return unless message['id'] && message['method']

        write({ jsonrpc: '2.0', id: message['id'], result: nil })
      end

      def write(payload)
        body = JSON.generate(payload)
        @stdin.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}")
        @stdin.flush
      end

      def read_message
        length = read_headers
        return nil if length.nil?

        body = @stdout.read(length)
        body && JSON.parse(body)
      end

      # Parse LSP headers, returning the Content-Length byte count (or nil at EOF).
      def read_headers
        length = nil
        while (line = @stdout.gets)
          line = line.strip
          break if line.empty? # blank line terminates the header block

          length = Regexp.last_match(1).to_i if line =~ /\AContent-Length:\s*(\d+)\z/i
        end
        length
      end

      def close
        [@stdin, @stdout, @stderr].compact.each { |io| io.close unless io.closed? }
        reap
      rescue StandardError
        nil
      ensure
        @started = false
      end

      # Closing the pipes makes a well-behaved server exit; escalate to TERM then
      # KILL so a hung server can never block the caller indefinitely.
      def reap
        return unless @wait&.alive?
        return if @wait.join(1)

        Process.kill('TERM', @wait.pid)
        return if @wait.join(2)

        Process.kill('KILL', @wait.pid)
      rescue StandardError
        nil
      end
    end
  end
end
