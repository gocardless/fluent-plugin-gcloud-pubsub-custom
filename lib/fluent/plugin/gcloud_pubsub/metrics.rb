# frozen_string_literal: true

module Fluent
  module GcloudPubSub
    # Utilities for interacting with Prometheus metrics
    module Metrics
      def self.register_or_existing(metric_name)
        return ::Prometheus::Client.registry.get(metric_name) if ::Prometheus::Client.registry.exist?(metric_name)

        yield
      end

      # Time the elapsed execution of the provided block, return the duration
      # as the first element followed by the result of the block.
      def self.measure_duration
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        finish = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        [finish - start, *result]
      end
    end
  end
end
