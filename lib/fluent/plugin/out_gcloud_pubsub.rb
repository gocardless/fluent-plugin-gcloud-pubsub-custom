# frozen_string_literal: true

require "fluent/plugin/output"
require "fluent/plugin/gcloud_pubsub/client"
require "fluent/plugin/gcloud_pubsub/metrics"
require "fluent/plugin_helper/inject"
require "prometheus/client"

module Fluent::Plugin
  class GcloudPubSubOutput < Output
    include Fluent::PluginHelper::Inject

    Fluent::Plugin.register_output("gcloud_pubsub", self)

    helpers :compat_parameters, :formatter

    DEFAULT_BUFFER_TYPE = "memory"
    DEFAULT_FORMATTER_TYPE = "json"

    desc "Set your GCP project."
    config_param :project, :string, default: nil
    desc "Set your credential file path."
    config_param :key, :string, default: nil
    desc "Set topic name to publish."
    config_param :topic, :string
    desc "If set to `true`, specified topic will be created when it doesn't exist."
    config_param :autocreate_topic, :bool, default: false
    desc "Publishing messages count per request to Cloud Pub/Sub."
    config_param :max_messages, :integer, default: 1000
    desc "Publishing messages bytesize per request to Cloud Pub/Sub."
    config_param :max_total_size, :integer, default: 9_800_000 # 9.8MB
    desc "Limit bytesize per message."
    config_param :max_message_size, :integer, default: 4_000_000 # 4MB
    desc "Extract these fields from the record and send them as attributes on the Pub/Sub message. " \
         "Cannot be set if compress_batches is enabled."
    config_param :attribute_keys, :array, default: []
    desc "The prefix for Prometheus metric names"
    config_param :metric_prefix, :string, default: "fluentd_output_gcloud_pubsub"
    desc "If set to `true`, messages will be batched and compressed before publication"
    config_param :compress_batches, :bool, default: false

    config_section :buffer do
      config_set_default :@type, DEFAULT_BUFFER_TYPE
    end

    config_section :format do
      config_set_default :@type, DEFAULT_FORMATTER_TYPE
    end

    # rubocop:disable Metrics/MethodLength
    def configure(conf)
      compat_parameters_convert(conf, :buffer, :formatter)
      super
      placeholder_validate!(:topic, @topic)
      @formatter = formatter_create

      if @compress_batches && !@attribute_keys.empty?
        # The attribute_keys option is implemented by extracting keys from the
        # record and setting them on the Pub/Sub message.
        # This is not possible in compressed mode, because we're sending just a
        # single Pub/Sub message that comprises many records, therefore the
        # attribute keys would clash.
        raise Fluent::ConfigError, ":attribute_keys cannot be used when compression is enabled"
      end

      @messages_published =
        Fluent::GcloudPubSub::Metrics.register_or_existing(:"#{@metric_prefix}_messages_published_per_batch") do
          ::Prometheus::Client.registry.histogram(
            :"#{@metric_prefix}_messages_published_per_batch",
            "Number of records published to Pub/Sub per buffer flush",
            {},
            [1, 10, 50, 100, 250, 500, 1000],
          )
        end

      @bytes_published =
        Fluent::GcloudPubSub::Metrics.register_or_existing(:"#{@metric_prefix}_messages_published_bytes") do
          ::Prometheus::Client.registry.histogram(
            :"#{@metric_prefix}_messages_published_bytes",
            "Total size in bytes of the records published to Pub/Sub",
            {},
            [100, 1000, 10_000, 100_000, 1_000_000, 5_000_000, 10_000_000],
          )
        end

      @compression_enabled =
        Fluent::GcloudPubSub::Metrics.register_or_existing(:"#{@metric_prefix}_compression_enabled") do
          ::Prometheus::Client.registry.gauge(
            :"#{@metric_prefix}_compression_enabled",
            "Whether compression/batching is enabled",
            {},
          )
        end
      @compression_enabled.set(common_labels, @compress_batches ? 1 : 0)
    end
    # rubocop:enable Metrics/MethodLength

    def start
      super
      @publisher = Fluent::GcloudPubSub::Publisher.new @project, @key, @autocreate_topic, @metric_prefix
    end

    def format(tag, time, record)
      record = inject_values_to_record(tag, time, record)
      attributes = {}
      @attribute_keys.each do |key|
        attributes[key] = record.delete(key)
      end
      [@formatter.format(tag, time, record), attributes].to_msgpack
    end

    def formatted_to_msgpack_binary?
      true
    end

    def multi_workers_ready?
      true
    end

    def write(chunk)
      topic = extract_placeholders(@topic, chunk.metadata)

      messages = []
      size = 0

      chunk.msgpack_each do |msg, attr|
        msg = Fluent::GcloudPubSub::Message.new(msg, attr)
        if msg.bytesize > @max_message_size
          log.warn "Drop a message because its size exceeds `max_message_size`", size: msg.bytesize
          next
        end
        if messages.length + 1 > @max_messages || size + msg.bytesize > @max_total_size
          publish(topic, messages)
          messages = []
          size = 0
        end
        messages << msg
        size += msg.bytesize
      end

      publish(topic, messages) unless messages.empty?
    rescue Fluent::GcloudPubSub::RetryableError => e
      log.warn "Retryable error occurs. Fluentd will retry.", error_message: e.to_s, error_class: e.class.to_s
      raise e
    rescue StandardError => e
      log.error "unexpected error", error_message: e.to_s, error_class: e.class.to_s
      log.error_backtrace
      raise e
    end

    private

    def publish(topic, messages)
      size = messages.map(&:bytesize).inject(:+)
      log.debug "send message topic:#{topic} length:#{messages.length} size:#{size}"

      @messages_published.observe(common_labels, messages.length)
      @bytes_published.observe(common_labels, size)

      @publisher.publish(topic, messages, @compress_batches)
    end

    def common_labels
      { topic: @topic }
    end
  end
end
