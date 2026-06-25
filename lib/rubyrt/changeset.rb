# frozen_string_literal: true

require 'rugged'
require 'fileutils'

module Rubyrt
  # Represents a set of changed files between two git refs, or all tracked
  # files in the repository when `all: true`.
  class Changeset
    attr_reader :base_ref, :head_ref

    def initialize(repo_path: Dir.pwd, base_ref: nil, head_ref: 'HEAD', all: false, filters: nil, exclude_files: nil,
                   merge_base: true)
      @repo = Rugged::Repository.discover(repo_path)
      @head_ref = head_ref || 'HEAD'
      @base_ref = base_ref || default_base_ref
      @all = all
      @filters = Array(filters)
      @exclude_files = Array(exclude_files)
      @merge_base = merge_base
    end

    def files
      @files ||= build_files
    end

    def diff_text_for(file)
      return full_content_for(file) if @all

      patch = patch_for(file)
      return nil if patch.nil? || patch.delta.binary

      patch.to_s.force_encoding('UTF-8')
    end

    # Absolute path to the repository working directory, used to launch tools
    # (e.g. a language server) against the code being reviewed.
    def workdir
      @repo.workdir
    end

    def full_content_for(file)
      blob = blob_at(file)
      return nil if blob.nil? || blob.binary?

      blob.content.dup.force_encoding('UTF-8')
    end

    private

    # Look up the blob for a path in the head commit's tree. Returns nil when
    # the path is absent or not a blob (e.g. a submodule or tree entry).
    def blob_at(file)
      entry = head_commit.tree.path(file)
      return nil unless entry[:type] == :blob

      @repo.lookup(entry[:oid])
    rescue Rugged::TreeError
      nil
    end

    def head_commit
      @head_commit ||= peel_to_commit(@repo.rev_parse(@head_ref))
    end

    def base_commit
      @base_commit ||= resolve_base_commit
    end

    def resolve_base_commit
      base = peel_to_commit(@repo.rev_parse(@base_ref))
      return base unless @merge_base

      oid = @repo.merge_base(base, head_commit)
      oid ? @repo.lookup(oid) : base
    end

    # rev_parse can return an annotated tag rather than a commit; peel it so
    # callers always get something that responds to #tree.
    def peel_to_commit(object)
      object = object.target while object.respond_to?(:target) && !object.is_a?(Rugged::Commit)
      object
    end

    def default_base_ref
      %w[main master].find { |ref| branch_exists?(ref) } || 'HEAD~1'
    end

    def branch_exists?(name)
      @repo.branches.exist?(name)
    end

    def patch_for(file)
      patches_by_path[file]
    end

    # Index patches by both old and new path once, so per-file lookups during
    # review are O(1) instead of re-scanning every patch.
    def patches
      @patches ||= diff.patches.to_a
    end

    def patches_by_path
      @patches_by_path ||= patches.each_with_object({}) do |patch, map|
        [patch.delta.old_file[:path], patch.delta.new_file[:path]].compact.each do |path|
          map[path] = patch
        end
      end
    end

    def diff
      # Diff the trees explicitly rather than relying on commit coercion.
      @diff ||= @repo.diff(base_commit.tree, head_commit.tree)
    end

    def build_files
      files = @all ? all_tracked_files : changed_file_paths
      apply_filters(apply_excludes(files))
    end

    # Paths changed between base and head, with binary file deltas removed.
    # Rugged marks a delta as binary when the underlying blob contains NUL
    # bytes, so text files in non-UTF-8 encodings are still reviewed.
    def changed_file_paths
      patches.reject { |patch| patch.delta.binary }
             .map { |patch| patch.delta.new_file[:path] }
             .compact.uniq
    end

    def apply_excludes(files)
      return files if @exclude_files.empty?

      files.reject { |file| @exclude_files.any? { |pattern| File.fnmatch?(pattern, file, File::FNM_PATHNAME | File::FNM_EXTGLOB) } }
    end

    def apply_filters(files)
      return files if @filters.empty?

      files.select { |file| @filters.any? { |pattern| File.fnmatch?(pattern, file, File::FNM_PATHNAME | File::FNM_EXTGLOB) } }
    end

    def all_tracked_files
      files = []
      head_commit.tree.walk(:preorder) do |root, entry|
        next unless entry[:type] == :blob

        path = root.empty? ? entry[:name] : "#{root}#{entry[:name]}"
        files << path
      end
      files.uniq
    end
  end
end
