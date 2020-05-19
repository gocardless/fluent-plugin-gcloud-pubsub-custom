# frozen_string_literal: true

require "google/cloud/pubsub"
require "zlib"

module Fluent
  module GcloudPubSub
    class Error < StandardError
    end
    class RetryableError < Error
    end

    COMPRESSION_ALGORITHM_ZLIB = "zlib"
    # 30 is the ASCII record separator character
    BATCHED_RECORD_SEPARATOR = 30.chr

    class Message
      attr_reader :message, :attributes

      def initialize(message, attributes = {})
        @message = message
        @attributes = attributes
      end

      def bytesize
        attr_size = 0
        @attributes.each do |key, val|
          attr_size += key.bytesize + val.bytesize
        end
        @message.bytesize + attr_size
      end
    end

    class Publisher
      def initialize(project, key, autocreate_topic, metric_prefix)
        @pubsub = Google::Cloud::Pubsub.new project_id: project, credentials: key
        @autocreate_topic = autocreate_topic
        @topics = {}

        # rubocop:disable Layout/LineLength
        @compression_ratio =
          Fluent::GcloudPubSub::Metrics.register_or_existing(:"#{metric_prefix}_messages_compressed_size_per_original_size_ratio") do
            ::Prometheus::Client.registry.histogram(
              :"#{metric_prefix}_messages_compressed_size_per_original_size_ratio",
              "Compression ratio achieved on a batch of messages",
              {},
              # We expect compression for even a single message to be typically
              # above 2x (0.5/50%), so bias the buckets towards the higher end
              # of the range.
              [0, 0.25, 0.5, 0.75, 0.85, 0.9, 0.95, 0.975, 1],
            )
          end

        @compression_duration =
          Fluent::GcloudPubSub::Metrics.register_or_existing(:"#{metric_prefix}_messages_compression_duration_seconds") do
            ::Prometheus::Client.registry.histogram(
              :"#{metric_prefix}_messages_compression_duration_seconds",
              "Time taken to compress a batch of messages",
              {},
              [0, 0.0001, 0.0005, 0.001, 0.01, 0.05, 0.1, 0.25, 0.5, 1],
            )
          end
        # rubocop:enable Layout/LineLength
      end

      def topic(topic_name)
        return @topics[topic_name] if @topics.key? topic_name

        client = @pubsub.topic topic_name
        client = @pubsub.create_topic topic_name if client.nil? && @autocreate_topic
        raise Error, "topic:#{topic_name} does not exist." if client.nil?

        @topics[topic_name] = client
        client
      end

      def publish(topic_name, messages, compress_batches = false)
        if compress_batches
          topic(topic_name).publish(*compress_messages_with_zlib(messages, topic_name))
        else
          topic(topic_name).publish do |batch|
            messages.each do |m|
              batch.publish m.message, m.attributes
            end
          end
        end
      rescue Google::Cloud::UnavailableError, Google::Cloud::DeadlineExceededError, Google::Cloud::InternalError => e
        raise RetryableError, "Google api returns error:#{e.class} message:#{e}"
      end

      private

      def compress_messages_with_zlib(messages, topic_name)
        original_size = messages.sum(&:bytesize)
        # This should never happen, only a programming error or major
        # misconfiguration should lead to this situation. But checking against
        # it here avoids a potential division by zero later on.
        raise ArgumentError, "not compressing empty inputs" if original_size.zero?

        # Here we're implicitly dropping the 'attributes' field of the messages
        # that we're iterating over.
        # This is fine, because the :attribute_keys config param is not
        # supported when in compressed mode, so this field will always be
        # empty.
        packed_messages = messages.map(&:message).join(BATCHED_RECORD_SEPARATOR)

        duration, compressed_messages = Fluent::GcloudPubSub::Metrics.measure_duration do
          Zlib::Deflate.deflate(packed_messages)
        end

        @compression_duration.observe(
          { topic: topic_name, algorithm: COMPRESSION_ALGORITHM_ZLIB },
          duration,
        )

        compressed_size = compressed_messages.bytesize
        @compression_ratio.observe(
          { topic: topic_name, algorithm: COMPRESSION_ALGORITHM_ZLIB },
          # If original = 1MiB and compressed = 256KiB; then metric value = 0.75 = 75% when plotted
          1 - compressed_size.to_f / original_size,
        )

        [compressed_messages, { "compression_algorithm": COMPRESSION_ALGORITHM_ZLIB }]
      end
    end

    class Subscriber
      def initialize(project, key, topic_name, subscription_name)
        pubsub = Google::Cloud::Pubsub.new project_id: project, credentials: key
        if topic_name.nil?
          @client = pubsub.subscription subscription_name
        else
          topic = pubsub.topic topic_name
          @client = topic.subscription subscription_name
        end
        raise Error, "subscription:#{subscription_name} does not exist." if @client.nil?
      end

      def pull(immediate, max)
        @client.pull immediate: immediate, max: max
      rescue Google::Cloud::UnavailableError, Google::Cloud::DeadlineExceededError, Google::Cloud::InternalError => e
        raise RetryableError, "Google pull api returns error:#{e.class} message:#{e}"
      end

      def acknowledge(messages)
        @client.acknowledge messages
      rescue Google::Cloud::UnavailableError, Google::Cloud::DeadlineExceededError, Google::Cloud::InternalError => e
        raise RetryableError, "Google acknowledge api returns error:#{e.class} message:#{e}"
      end
    end

    class MessageUnpacker
      def self.unpack(message)
        attributes = message.attributes
        algorithm = attributes["compression_algorithm"]

        case algorithm
        when nil
          # For an uncompressed message return the single line and attributes
          [[message.message.data.chomp, message.attributes]]
        when COMPRESSION_ALGORITHM_ZLIB
          # Return all of the lines in the message, with empty attributes
          Zlib::Inflate
            .inflate(message.message.data)
            .split(BATCHED_RECORD_SEPARATOR)
            .map { |line| [line, {}] }
        else
          raise ArgumentError, "unknown compression algorithm: '#{algorithm}'"
        end
      end
    end
  end
end
