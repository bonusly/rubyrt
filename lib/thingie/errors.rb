# frozen_string_literal: true

module Thingie
  # Raised when required configuration is missing or invalid.
  class ConfigurationError < StandardError
  end

  # Raised when a language server fails to start or respond.
  class LspError < StandardError
  end
end
