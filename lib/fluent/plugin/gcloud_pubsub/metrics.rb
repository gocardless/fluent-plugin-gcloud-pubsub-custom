# frozen_string_literal: true

module Fluent
  module GcloudPubSub
    # Utilities for interacting with Prometheus metrics
    module Metrics
      def self.register_or_existing(metric_name)
        return ::Prometheus::Client.registry.get(metric_name) if ::Prometheus::Client.registry.exist?(metric_name)

        yield
      end
    end
  end
end
