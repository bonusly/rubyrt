# frozen_string_literal: true

module Rubyrt
  module Schemas
    # JSON schema for the critic pass: a single verdict on one finding.
    # `reasoning` is required so the model must justify before deciding.
    VERDICT_SCHEMA = {
      name: 'rubyrt_finding_verdict',
      description: 'Verdict on whether a single review finding is real and should be kept',
      strict: true,
      schema: {
        type: 'object',
        properties: {
          verdict: { type: 'string', enum: %w[uphold reject] },
          reasoning: { type: 'string' }
        },
        required: %w[verdict reasoning],
        additionalProperties: false
      }
    }.freeze
  end
end
