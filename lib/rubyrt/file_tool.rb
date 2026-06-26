# frozen_string_literal: true

require 'ruby_llm'

module Rubyrt
  # RubyLLM tool that lets the model check whether a path relative to the working
  # directory exists, and read its contents when it is a non-binary file. Paths
  # are constrained to stay within the working directory: any attempt to escape
  # it (via `..`, absolute paths, or symlinks pointing outside) is rejected.
  class FileTool < RubyLLM::Tool
    # Number of leading bytes inspected to decide whether a file is binary. A
    # NUL byte anywhere in this window, or a UTF-8 decoding failure, marks the
    # file as binary so we never dump non-textual bytes into the model context.
    SNIFF_BYTES = 8192

    description <<~DESC
      Check whether a path relative to the working directory exists, and read its
      contents when it is a non-binary file. Paths cannot escape the working
      directory: `..`, absolute paths, and symlinks pointing outside it are
      rejected. Use this to inspect existing files for context during a review.
    DESC

    param :path, desc: 'Path relative to the working directory to inspect', required: true

    def initialize(root:)
      super()
      # Canonicalize the root so symlinked prefixes (e.g. /tmp -> /private/tmp
      # on macOS) match the realpath'd candidates compared against it.
      @root = File.realpath(root)
    end

    def execute(path:)
      resolved = resolve(path)
      return "Path `#{path}` is outside the working directory." if resolved.nil?
      return "Path `#{relative(resolved)}` does not exist." unless File.exist?(resolved)

      return "Path `#{relative(resolved)}` is a directory." if File.directory?(resolved)

      return "Path `#{relative(resolved)}` is not readable." unless File.readable?(resolved)

      return binary_message(resolved) if binary?(resolved)

      contents = File.read(resolved)
      "#{relative(resolved)}\n```\n#{contents}\n```"
    rescue StandardError => e
      "File lookup unavailable for `#{path}`: #{e.message}"
    end

    private

    # Expand `path` relative to the working directory, collapse every symlink in
    # the resulting path with `File.realpath`, and confirm the fully-resolved
    # target still sits inside the working directory. Resolving the whole path
    # (not just the final component) closes a traversal gap where a symlinked
    # intermediate directory points outside the root, and using the resolved path
    # for all subsequent reads avoids a Time-of-Check to Time-of-Use race.
    def resolve(path)
      candidate = File.expand_path(path, @root)
      resolved = realpath(candidate)
      return nil unless resolved

      inside?(resolved) ? resolved : nil
    end

    # `File.realpath` raises ENOENT for a non-existent leaf, so when the file
    # itself doesn't exist yet we resolve its parent directory (which must exist)
    # and reappend the basename. This still collapses symlinked intermediate
    # directories so a path like `link/missing.rb` is checked against the link's
    # real target rather than its on-disk name.
    def realpath(candidate)
      File.realpath(candidate)
    rescue Errno::ENOENT
      parent = File.dirname(candidate)
      return candidate if parent == candidate # reached filesystem root

      File.join(File.realpath(parent), File.basename(candidate))
    rescue StandardError
      nil
    end

    def inside?(path)
      path == @root || path.start_with?("#{@root}#{File::SEPARATOR}")
    end

    # Treat a file as binary when its leading bytes contain a NUL byte or fail to
    # decode as UTF-8, mirroring the heuristic git uses for text/binary detection.
    def binary?(path)
      head = File.binread(path, SNIFF_BYTES) || ''
      return true if head.include?("\0")

      head.force_encoding('UTF-8')
      !head.valid_encoding?
    rescue StandardError
      true
    end

    def binary_message(path)
      "Path `#{relative(path)}` exists but is a binary file; contents are not available."
    end

    def relative(path)
      path.start_with?("#{@root}#{File::SEPARATOR}") ? path.delete_prefix("#{@root}#{File::SEPARATOR}") : path
    end
  end
end
