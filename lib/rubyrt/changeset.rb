# frozen_string_literal: true

require 'rugged'
require 'fileutils'

module Rubyrt
  # Represents a set of changed files between two git refs, or all tracked
  # files in the repository when `all: true`.
  class Changeset
    attr_reader :base_ref, :head_ref

    def initialize(repo_path: Dir.pwd, base_ref: nil, head_ref: 'HEAD', all: false)
      @repo = Rugged::Repository.discover(repo_path)
      @head_ref = head_ref || 'HEAD'
      @base_ref = base_ref || default_base_ref
      @all = all
    end

    def files
      @files ||= build_files
    end

    def diff_text_for(file)
      return full_content_for(file) if @all

      patch_for(file)&.to_s&.force_encoding('UTF-8')
    end

    def full_content_for(file)
      blob = @repo.lookup(head_commit.tree.path(file)[:oid])
      return nil if blob.nil?

      blob.content.force_encoding('UTF-8')
    rescue Rugged::TreeError
      nil
    end

    private

    def head_commit
      @repo.lookup(@repo.rev_parse(@head_ref).oid)
    end

    def base_commit
      @repo.lookup(@repo.rev_parse(@base_ref).oid)
    end

    def default_base_ref
      %w[main master].find { |ref| branch_exists?(ref) } || 'HEAD~1'
    end

    def branch_exists?(name)
      @repo.branches.exist?(name)
    end

    def patch_for(file)
      diff.patches.find { |p| p.delta.old_file[:path] == file || p.delta.new_file[:path] == file }
    end

    def diff
      @diff ||= @repo.diff(base_commit, head_commit)
    end

    def build_files
      return all_tracked_files if @all

      diff.patches.map do |patch|
        patch.delta.new_file[:path]
      end.compact.uniq
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
