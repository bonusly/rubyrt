# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Thingie::PostProcessor do
  def issue(confidence:, severity:)
    instance_double(Thingie::Issue, confidence: confidence, severity: severity)
  end

  let(:issues) do
    [issue(confidence: 1, severity: 2), issue(confidence: 2, severity: 2), issue(confidence: 1, severity: 4)]
  end

  it 'keeps only issues within the confidence and severity maximums' do
    kept = described_class.new('max_confidence' => 1, 'max_severity' => 3).call(issues)
    expect(kept).to eq([issues.first])
  end

  it 'keeps everything when no thresholds are configured' do
    expect(described_class.new(nil).call(issues)).to eq(issues)
  end
end
