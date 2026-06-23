# frozen_string_literal: true

module Rubyrt
  # JSON schema for LLM review responses, used to enforce structured output
  # and avoid markdown-wrapped or malformed JSON.
  module Schemas
    ISSUE_SCHEMA = {
      name: 'rubyrt_review_issues',
      description: 'Array of code review issues found in the diff',
      strict: true,
      schema: {
        type: 'object',
        properties: {
          issues: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                title: { type: 'string' },
                details: { type: 'string' },
                tags: {
                  type: 'array',
                  items: { type: 'string' }
                },
                severity: { type: 'integer' },
                confidence: { type: 'integer' },
                affected_lines: {
                  type: 'array',
                  items: {
                    type: 'object',
                    properties: {
                      start_line: { type: 'integer' },
                      end_line: { type: 'integer' },
                      proposal: { type: 'string' }
                    },
                    required: %w[start_line],
                    additionalProperties: false
                  }
                }
              },
              required: %w[title details tags severity confidence affected_lines],
              additionalProperties: false
            }
          }
        },
        required: %w[issues],
        additionalProperties: false
      }
    }.freeze
  end
end
