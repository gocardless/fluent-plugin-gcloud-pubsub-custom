# frozen_string_literal: true

require "json"
require "webrick"

require "fluent/plugin/input"
require "fluent/plugin/parser"

require "fluent/plugin/gcloud_pubsub/client"
require "fluent/plugin/gcloud_pubsub/metrics"

module Fluent::Plugin
  class GcloudPubSubInput < Input
    Fluent::Plugin.register_input("gcloud_pubsub", self)

    helpers :compat_parameters, :parser, :thread

    DEFAULT_PARSER_TYPE = "json"

    class FailedParseError < StandardError
    end

    desc "Set tag of messages."
    config_param :tag, :string
    desc "Set key to be used as tag."
    config_param :tag_key, :string, default: nil
    desc "Set your GCP project."
    config_param :project, :string, default: nil
    desc "Set your credential file path."
    config_param :key, :string, default: nil
    desc "Set topic name to pull."
    config_param :topic, :string, default: nil
    desc "Set subscription name to pull."
    config_param :subscription, :string
    desc "Pulling messages by intervals of specified seconds."
    config_param :pull_interval, :float, default: 5.0
    desc "Max messages pulling at once."
    config_param :max_messages, :integer, default: 100
    desc "Setting `true`, keepalive connection to wait for new messages."
    config_param :return_immediately, :bool, default: true
    desc "Set number of threads to pull messages."
    config_param :pull_threads, :integer, default: 1
    desc "Acquire these fields from attributes on the Pub/Sub message and merge them into the record"
    config_param :attribute_keys,     :array, default: []
    desc "Set error type when parsing messages fails."
    config_param :parse_error_action, :enum, default: :exception, list: %i[exception warning]
    desc "The prefix for Prometheus metric names"
    config_param :metric_prefix, :string, default: "fluentd_input_gcloud_pubsub"
    # for HTTP RPC
    desc "If `true` is specified, HTTP RPC to stop or start pulling message is enabled."
    config_param :enable_rpc, :bool, default: false
    desc "Bind IP address for HTTP RPC."
    config_param :rpc_bind, :string, default: "0.0.0.0"
    desc "Port for HTTP RPC."
    config_param :rpc_port, :integer, default: 24_680

    config_section :parse do
      config_set_default :@type, DEFAULT_PARSER_TYPE
    end

    class RPCServlet < WEBrick::HTTPServlet::AbstractServlet
      class Error < StandardError; end

      def initialize(server, plugin)
        super
        @plugin = plugin
      end

      # rubocop:disable Naming/MethodName
      def do_GET(req, res)
        begin
          code, header, body = process(req, res)
        rescue StandardError
          code, header, body = render_json(500, {
                                             "ok" => false,
                                             "message" => "Internal Server Error",
                                             "error" => $ERROR_INFO.to_s,
                                             "backtrace" => $ERROR_INFO.backtrace,
                                           })
        end

        res.status = code
        header.each_pair do |k, v|
          res[k] = v
        end
        res.body = body
      end
      # rubocop:enable Naming/MethodName

      def render_json(code, obj)
        [code, { "Content-Type" => "application/json" }, obj.to_json]
      end

      def process(req, _res)
        ret = { "ok" => true }
        case req.path_info
        when "/stop"
          @plugin.stop_pull
        when "/start"
          @plugin.start_pull
        when "/status"
          ret["status"] = @plugin.status_of_pull
        else
          raise Error, "Invalid path_info: #{req.path_info}"
        end
        render_json(200, ret)
      end
    end

    # rubocop:disable Metrics/MethodLength
    def configure(conf)
      compat_parameters_convert(conf, :parser)
      super
      @rpc_srv = nil
      @rpc_thread = nil
      @stop_pull = false

      @extract_tag = if @tag_key.nil?
                       method(:static_tag)
                     else
                       method(:dynamic_tag)
                     end

      @parser = parser_create

      @messages_pulled =
        Fluent::GcloudPubSub::Metrics.register_or_existing(:"#{@metric_prefix}_messages_pulled") do
          ::Prometheus::Client.registry.histogram(
            :"#{@metric_prefix}_messages_pulled",
            "Number of Pub/Sub messages pulled by the subscriber on each invocation",
            {},
            [0, 1, 10, 50, 100, 250, 500, 1000],
          )
        end

      @messages_pulled_bytes =
        Fluent::GcloudPubSub::Metrics.register_or_existing(:"#{@metric_prefix}_messages_pulled_bytes") do
          ::Prometheus::Client.registry.histogram(
            :"#{@metric_prefix}_messages_pulled_bytes",
            "Total size in bytes of the Pub/Sub messages pulled by the subscriber on each invocation",
            {},
            [100, 1000, 10_000, 100_000, 1_000_000, 5_000_000, 10_000_000],
          )
        end

      @pull_errors =
        Fluent::GcloudPubSub::Metrics.register_or_existing(:"#{@metric_prefix}_pull_errors_total") do
          ::Prometheus::Client.registry.counter(
            :"#{@metric_prefix}_pull_errors_total",
            "Errors encountered while pulling or processing messages",
            {},
          )
        end
    end
    # rubocop:enable Metrics/MethodLength

    def start
      super
      start_rpc if @enable_rpc

      @subscriber = Fluent::GcloudPubSub::Subscriber.new @project, @key, @topic, @subscription
      log.debug "connected subscription:#{@subscription} in project #{@project}"

      @emit_guard = Mutex.new
      @stop_subscribing = false
      @subscribe_threads = []
      @pull_threads.times do |idx|
        @subscribe_threads.push thread_create("in_gcloud_pubsub_subscribe_#{idx}".to_sym, &method(:subscribe))
      end
    end

    def shutdown
      if @rpc_srv
        @rpc_srv.shutdown
        @rpc_srv = nil
      end
      @rpc_thread = nil if @rpc_thread
      @stop_subscribing = true
      @subscribe_threads.each(&:join)
      super
    end

    def stop_pull
      @stop_pull = true
      log.info "stop pull from subscription:#{@subscription}"
    end

    def start_pull
      @stop_pull = false
      log.info "start pull from subscription:#{@subscription}"
    end

    def status_of_pull
      @stop_pull ? "stopped" : "started"
    end

    private

    def static_tag(_record)
      @tag
    end

    def dynamic_tag(record)
      record.delete(@tag_key) || @tag
    end

    def start_rpc
      log.info "listening http rpc server on http://#{@rpc_bind}:#{@rpc_port}/"
      @rpc_srv = WEBrick::HTTPServer.new(
        {
          BindAddress: @rpc_bind,
          Port: @rpc_port,
          Logger: WEBrick::Log.new(STDERR, WEBrick::Log::FATAL),
          AccessLog: [],
        },
      )
      @rpc_srv.mount("/api/in_gcloud_pubsub/pull/", RPCServlet, self)
      @rpc_thread = thread_create(:in_gcloud_pubsub_rpc_thread) do
        @rpc_srv.start
      end
    end

    def subscribe
      until @stop_subscribing
        _subscribe unless @stop_pull

        sleep @pull_interval if @return_immediately || @stop_pull
      end
    rescue StandardError => e
      log.error "unexpected error", error_message: e.to_s, error_class: e.class.to_s
      log.error_backtrace e.backtrace
    end

    def _subscribe
      messages = @subscriber.pull @return_immediately, @max_messages
      @messages_pulled.observe(common_labels, messages.size)
      if messages.empty?
        log.debug "no messages are pulled"
        return
      end

      messages_size = messages.sum do |message|
        message.data.bytesize + message.attributes.sum { |k, v| k.bytesize + v.bytesize }
      end
      @messages_pulled_bytes.observe(common_labels, messages_size)

      process messages
      @subscriber.acknowledge messages

      log.debug "#{messages.length} message(s) processed"
    rescue Fluent::GcloudPubSub::RetryableError => e
      @pull_errors.increment(common_labels.merge({ retryable: true }))
      log.warn "Retryable error occurs. Fluentd will retry.", error_message: e.to_s, error_class: e.class.to_s
    rescue StandardError => e
      @pull_errors.increment(common_labels.merge({ retryable: false }))
      log.error "unexpected error", error_message: e.to_s, error_class: e.class.to_s
      log.error_backtrace e.backtrace
    end

    def process(messages)
      event_streams = Hash.new do |hsh, key|
        hsh[key] = Fluent::MultiEventStream.new
      end

      messages.each do |m|
        lines_attributes = Fluent::GcloudPubSub::MessageUnpacker.unpack(m)

        lines_attributes.each do |line, attributes|
          @parser.parse(line) do |time, record|
            if time && record
              @attribute_keys.each do |key|
                record[key] = attributes[key]
              end

              event_streams[@extract_tag.call(record)].add(time, record)
            else
              case @parse_error_action
              when :exception
                raise FailedParseError, "pattern not match: #{line}"
              else
                log.warn "pattern not match", record: line
              end
            end
          end
        end
      end

      event_streams.each do |tag, es|
        # There are some output plugins not to supposed to be called with multi-threading.
        # Maybe remove in the future.
        @emit_guard.synchronize do
          router.emit_stream(tag, es)
        end
      end
    end

    def common_labels
      { subscription: @subscription }
    end
  end
end
