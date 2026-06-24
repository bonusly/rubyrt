# frozen_string_literal: true

require 'rugged'
require 'fileutils'

module Rubyrt
  # Represents a set of changed files between two git refs, or all tracked
  # files in the repository when `all: true`.
  class Changeset
    attr_reader :base_ref, :head_ref

    def initialize(repo_path: Dir.pwd, base_ref: nil, head_ref: 'HEAD', all: false, filters: nil, merge_base: true)
      @repo = Rugged::Repository.discover(repo_path)
      @head_ref = head_ref || 'HEAD'
      @base_ref = base_ref || default_base_ref
      @all = all
      @filters = Array(filters)
      @merge_base = merge_base
    end

    def files
      @files ||= build_files
    end

    def diff_text_for(file)
      return full_content_for(file) if @all

      patch_for(file)&.to_s&.force_encoding('UTF-8')
    end

    def full_content_for(file)
      entry = head_commit.tree.path(file)
      return nil unless entry[:type] == :blob

      blob = @repo.lookup(entry[:oid])
      return nil if blob.nil?

      blob.content.dup.force_encoding('UTF-8')
    rescue Rugged::TreeError
      nil
    end

    private

    def head_commit
      @head_commit ||= @repo.rev_parse(@head_ref)
    end

    def base_commit
      @base_commit ||= resolve_base_commit
    end

    def resolve_base_commit
      base = @repo.rev_parse(@base_ref)
      return base unless @merge_base

      oid = @repo.merge_base(base, head_commit)
      oid ? @repo.lookup(oid) : base
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
    def patches_by_path
      @patches_by_path ||= diff.patches.each_with_object({}) do |patch, map|
        map[patch.delta.old_file[:path]] = patch
        map[patch.delta.new_file[:path]] = patch
      end
    end

    def diff
      # Diff the trees explicitly rather than relying on commit coercion.
      @diff ||= @repo.diff(base_commit.tree, head_commit.tree)
    end

    def build_files
      files = @all ? all_tracked_files : diff.patches.map { |patch| patch.delta.new_file[:path] }.compact.uniq
      apply_filters(files)
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
