# frozen_string_literal: true

module Thingie
  # Thin wrapper around ENV. Every environment-variable read/write in the app
  # goes through this class instead of touching ENV directly, so specs can
  # swap in a fixed, isolated set of variables via Env.store= instead of
  # mutating and restoring the real process environment (which risks leaking
  # a developer's actual shell exports or ~/.thingie/.env into test behavior).
  class Env
    class << self
      # Fetches the value of an environment variable, or a default if unset.
      #
      # @param key [String, Symbol] the variable name
      # @param default [Object, nil] the value returned when `key` is not set
      # @return [Object, nil] the variable's value, or `default`
      def fetch(key, default = nil)
        store.fetch(key.to_s, default)
      end

      # Reads an environment variable.
      #
      # @param key [String, Symbol] the variable name
      # @return [String, nil] the variable's value, or `nil` if unset
      def [](key)
        store[key.to_s]
      end

      # Sets an environment variable.
      #
      # @param key [String, Symbol] the variable name
      # @param value [String] the value to store
      # @return [String] the assigned value
      def []=(key, value)
        store[key.to_s] = value
      end

      # Checks whether an environment variable is set.
      #
      # @param key [String, Symbol] the variable name
      # @return [Boolean] true if the variable is present
      def key?(key)
        store.key?(key.to_s)
      end

      # Removes an environment variable.
      #
      # @param key [String, Symbol] the variable name
      # @return [String, nil] the removed value, or `nil` if it wasn't set
      def delete(key)
        store.delete(key.to_s)
      end

      # The backing store for all reads/writes.
      #
      # Defaults to the real ENV so production behavior is untouched; specs
      # replace this with a plain Hash to isolate themselves from the host
      # environment.
      #
      # @return [ENV, Hash] the current backing store
      def store
        @store ||= ENV
      end

      attr_writer :store
    end
  end
end
