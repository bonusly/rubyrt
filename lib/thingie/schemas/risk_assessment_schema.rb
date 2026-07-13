# frozen_string_literal: true

module Thingie
  module Schemas
    # JSON schema for the auto-approval risk assessment: a Low/Medium risk level
    # and a short reason grounded in the code change (regression, downtime, and
    # security risk) that justifies the approval.
    RISK_ASSESSMENT_SCHEMA = {
      name: 'rubyrt_risk_assessment',
      description: 'Regression/downtime/security risk of merging a pull request, for the approval reason',
      strict: true,
      schema: {
        type: 'object',
        properties: {
          risk_level: { type: 'string', enum: %w[Low Medium] },
          summary: { type: 'string' }
        },
        required: %w[risk_level summary],
        additionalProperties: false
      }
    }.freeze
  end
end
