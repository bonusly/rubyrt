# frozen_string_literal: true

module Rubyrt
  module Schemas
    # JSON schema for the auto-approval risk assessment: a residual-risk level
    # and a short human-readable summary of what passed and any remaining risk.
    RISK_ASSESSMENT_SCHEMA = {
      name: 'rubyrt_risk_assessment',
      description: 'Residual risk of auto-approving a pull request that passed all automated gates',
      strict: true,
      schema: {
        type: 'object',
        properties: {
          risk_level: { type: 'string', enum: %w[Low Medium High] },
          summary: { type: 'string' }
        },
        required: %w[risk_level summary],
        additionalProperties: false
      }
    }.freeze
  end
end
