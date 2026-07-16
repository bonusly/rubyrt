# frozen_string_literal: true

module Thingie
  # Thin wrapper around ENV. Every environment-variable read/write in the app
  # goes through this class instead of touching ENV directly, so specs can
  # swap in a fixed, isolated set of variables via Env.store= instead of
  # mutating and restoring the real process environment (which risks leaking
  # a developer's actual shell exports or ~/.thingie/.env into test behavior).
  class Env
    class << self
      def fetch(key, default = nil)
        store.fetch(key.to_s, default)
      end

      def [](key)
        store[key.to_s]
      end

      def []=(key, value)
        store[key.to_s] = value
      end

      def key?(key)
        store.key?(key.to_s)
      end

      def delete(key)
        store.delete(key.to_s)
      end

      # Defaults to the real ENV so production behavior is untouched; specs
      # replace this with a plain Hash to isolate themselves from the host
      # environment.
      def store
        @store ||= ENV
      end

      attr_writer :store
    end
  end
end
