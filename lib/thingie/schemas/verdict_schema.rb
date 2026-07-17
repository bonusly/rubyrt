# frozen_string_literal: true

module Thingie
  module Schemas
    # JSON schema for the critic pass: a single verdict on one finding, with
    # optional corrections to its severity/confidence grade. `reasoning` is
    # required so the model must justify before deciding. The overrides are
    # nullable rather than omittable because OpenAI strict-mode schemas require
    # every property to be listed in `required`.
    VERDICT_SCHEMA = {
      name: 'thingie_finding_verdict',
      description: 'Verdict on whether a single review finding is real and should be kept, ' \
                   'optionally correcting its severity/confidence grade',
      strict: true,
      schema: {
        type: 'object',
        properties: {
          verdict: { type: 'string', enum: %w[uphold reject] },
          severity_override: { type: %w[integer null] },
          confidence_override: { type: %w[integer null] },
          reasoning: { type: 'string' }
        },
        required: %w[verdict severity_override confidence_override reasoning],
        additionalProperties: false
      }
    }.freeze
  end
end
