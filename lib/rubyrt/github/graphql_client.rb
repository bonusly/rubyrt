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
        body = stringify(to_hash(response))
        raise_on_errors(body)
        body.dig('data', 'repository', 'pullRequest', 'reviewThreads', 'nodes') || []
      end

      def resolve_thread(thread_id)
        response = @client.post('/graphql',
                                query: resolve_thread_mutation,
                                variables: { threadId: thread_id })
        raise_on_errors(stringify(to_hash(response)))
        response
      end

      private

      # GraphQL returns HTTP 200 even on errors, signalling them via a top-level
      # `errors` array. Surface them instead of silently reporting no threads.
      def raise_on_errors(body)
        errors = Array(body['errors'])
        return if errors.empty?

        messages = errors.map { |e| e.is_a?(Hash) ? e['message'] || e.to_s : e.to_s }.join('; ')
        raise "GitHub GraphQL request failed: #{messages}"
      end

      # Octokit parses responses into Sawyer::Resource objects keyed by symbols.
      # `#to_attrs` recursively converts the resource into a plain Hash; tolerate
      # nil and raw Hash responses (e.g. from stubbed clients in tests).
      def to_hash(response)
        return {} if response.nil?
        return response.to_attrs if response.respond_to?(:to_attrs)

        response
      end

      # Recursively converts symbol keys to strings so both this client and its
      # downstream consumers can traverse the result with string keys.
      def stringify(value)
        case value
        when Hash
          value.each_with_object({}) { |(k, v), acc| acc[k.to_s] = stringify(v) }
        when Array
          value.map { |element| stringify(element) }
        else
          value
        end
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
