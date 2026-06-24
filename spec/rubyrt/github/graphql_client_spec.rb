# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Rubyrt::GitHub::GraphqlClient do # rubocop:disable RSpec/SpecFilePathFormat
  subject(:graphql_client) { described_class.new(client) }

  let(:client) { instance_double(Octokit::Client) }

  def nodes_response(nodes)
    { 'data' => { 'repository' => { 'pullRequest' => { 'reviewThreads' => { 'nodes' => nodes } } } } }
  end

  def stub_post(response)
    allow(client).to receive(:post).and_return(response)
  end

  def review_threads
    graphql_client.review_threads(owner: 'o', repo: 'r', pr_number: 1)
  end

  describe '#review_threads' do
    it 'returns the thread nodes from a Sawyer response with string keys' do
      resource = Sawyer::Resource.new(Sawyer::Agent.new('http://example.com'),
                                      nodes_response([{ 'id' => 'T1', 'isResolved' => false }]))
      stub_post(resource)

      expect(review_threads).to eq([{ 'id' => 'T1', 'isResolved' => false }])
    end

    it 'tolerates a raw Hash response with symbol keys' do
      stub_post(nodes_response([{ id: 'T2' }]))

      expect(review_threads).to eq([{ 'id' => 'T2' }])
    end

    it 'returns an empty array for a nil response' do
      stub_post(nil)

      expect(review_threads).to eq([])
    end

    it 'raises when the GraphQL payload contains errors' do
      stub_post({ 'errors' => [{ 'message' => 'Could not resolve to a Repository' }], 'data' => nil })

      expect { review_threads }.to raise_error(/GitHub GraphQL request failed: Could not resolve to a Repository/)
    end
  end
end
