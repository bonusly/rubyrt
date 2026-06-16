# frozen_string_literal: true

require 'rugged'
require 'fileutils'

module Rubyrt
  # Represents a set of changed files between two git refs.
  class Changeset
    attr_reader :base_ref, :head_ref

    def initialize(repo_path: Dir.pwd, base_ref: nil, head_ref: 'HEAD')
      @repo = Rugged::Repository.discover(repo_path)
      @head_ref = head_ref
      @base_ref = base_ref || default_base_ref
    end

    def files
      @files ||= build_files
    end

    def diff_text_for(file)
      patch_for(file)&.to_s
    end

    def full_content_for(file)
      head_commit.tree.path(file)[:oid]
      blob = @repo.lookup(head_commit.tree.path(file)[:oid])
      blob.content
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
      diff.patches.map do |patch|
        patch.delta.new_file[:path]
      end.compact.uniq
    end
  end
end
