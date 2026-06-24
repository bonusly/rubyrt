# frozen_string_literal: true

require 'json'

module Rubyrt
  module GitHub
    # Minimal GraphQL client wrapper around Octokit for resolving review threads.
    class GraphqlClient
      THREAD_PAGE_SIZE = 100

      def initialize(client)
        @client = client
      end

      def review_threads(owner:, repo:, pr_number:)
        response = @client.post('/graphql',
                                query: review_threads_query,
                                variables: thread_variables(owner, repo, pr_number))
        nodes = response.dig(:data, :repository, :pullRequest, :reviewThreads, :nodes) || []
        nodes.map { |node| stringify(node) }
      end

      def resolve_thread(thread_id)
        @client.post('/graphql',
                     query: resolve_thread_mutation,
                     variables: { threadId: thread_id })
      end

      private

      # Octokit parses responses into Sawyer::Resource objects keyed by symbols.
      # Convert each thread into a plain, deeply string-keyed Hash so downstream
      # consumers can traverse it with string keys.
      def stringify(resource)
        source = resource.respond_to?(:to_h) ? resource.to_h : resource
        JSON.parse(JSON.generate(source))
      end

      def review_threads_query
        <<~GRAPHQL
          query($owner: String!, $repo: String!, $pr_number: Int!, $first: Int!) {
            repository(owner: $owner, name: $repo) {
              pullRequest(number: $pr_number) {
                reviewThreads(first: $first) {
                  nodes {
                    id
                    isResolved
                    isOutdated
                    line
                    path
                    comments(first: 1) {
                      nodes {
                        author { login }
                        body
                      }
                    }
                  }
                }
              }
            }
          }
        GRAPHQL
      end

      def resolve_thread_mutation
        <<~GRAPHQL
          mutation($threadId: ID!) {
            resolveReviewThread(input: { threadId: $threadId }) {
              thread { id }
            }
          }
        GRAPHQL
      end

      def thread_variables(owner, repo, pr_number)
        {
          owner: owner,
          repo: repo,
          pr_number: pr_number,
          first: THREAD_PAGE_SIZE
        }
      end
    end
  end
end
