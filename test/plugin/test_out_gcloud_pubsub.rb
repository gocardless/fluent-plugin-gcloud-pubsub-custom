# frozen_string_literal: true

require "zlib"

require_relative "../test_helper"
require "fluent/test/driver/output"
require "fluent/test/helpers"

class GcloudPubSubOutputTest < Test::Unit::TestCase
  include Fluent::Test::Helpers

  CONFIG = %(
    project project-test
    topic topic-test
    key key-test
  )

  ReRaisedError = Class.new(RuntimeError)

  def create_driver(conf = CONFIG)
    Fluent::Test::Driver::Output.new(Fluent::Plugin::GcloudPubSubOutput).configure(conf)
  end

  setup do
    Fluent::Test.setup
  end

  setup do
    @time = event_time("2016-07-09 11:12:13 UTC")
  end

  sub_test_case "configure" do
    test "default values are configured" do
      d = create_driver(%(
        project project-test
        topic topic-test
        key key-test
      ))

      assert_equal("project-test", d.instance.project)
      assert_equal("topic-test", d.instance.topic)
      assert_equal("key-test", d.instance.key)
      assert_equal(false, d.instance.autocreate_topic)
      assert_equal(1000, d.instance.max_messages)
      assert_equal(9_800_000, d.instance.max_total_size)
      assert_equal(4_000_000, d.instance.max_message_size)
    end

    test '"topic" must be specified' do
      assert_raises Fluent::ConfigError do
        create_driver(%(
          project project-test
          key key-test
        ))
      end
    end

    test '"autocreate_topic" can be specified' do
      d = create_driver(%(
        project project-test
        topic topic-test
        key key-test
        autocreate_topic true
      ))

      assert_equal(true, d.instance.autocreate_topic)
    end

    test "'attribute_keys' cannot be used with 'compress_batches'" do
      assert_raise(Fluent::ConfigError.new(":attribute_keys cannot be used when compression is enabled")) do
        create_driver(%(
          project project-test
          topic topic-test
          attribute_keys attr-test
          compress_batches true
        ))
      end
    end
  end

  sub_test_case "topic" do
    setup do
      @publisher = mock!
      @pubsub_mock = mock!
      stub(Google::Cloud::Pubsub).new { @pubsub_mock }
    end

    test '"autocreate_topic" is enabled' do
      d = create_driver(%(
        project project-test
        topic topic-test
        key key-test
        autocreate_topic true
      ))

      @publisher.publish.once
      @pubsub_mock.topic("topic-test").once { nil }
      @pubsub_mock.create_topic("topic-test").once { @publisher }
      d.run(default_tag: "test") do
        d.feed(@time, { "a" => "b" })
      end
    end

    test "40x error occurred on connecting to Pub/Sub" do
      d = create_driver

      @pubsub_mock.topic("topic-test").once do
        raise Google::Cloud::NotFoundError, "TEST"
      end

      assert_raise Google::Cloud::NotFoundError do
        d.run(default_tag: "test") do
          d.feed(@time, { "a" => "b" })
        end
      end
    end

    test "50x error occurred on connecting to Pub/Sub" do
      d = create_driver

      @pubsub_mock.topic("topic-test").once do
        raise Google::Cloud::UnavailableError, "TEST"
      end

      assert_raise Fluent::GcloudPubSub::RetryableError do
        d.run(default_tag: "test") do
          d.feed(@time, { "a" => "b" })
        end
      end
    end

    test "topic is nil" do
      d = create_driver

      @pubsub_mock.topic("topic-test").once { nil }

      assert_raise Fluent::GcloudPubSub::Error do
        d.run(default_tag: "test") do
          d.feed(@time, { "a" => "b" })
        end
      end
    end

    test 'messages exceeding "max_message_size" are not published' do
      d = create_driver(%(
        project project-test
        topic topic-test
        key key-test
        max_message_size 1000
      ))

      @publisher.publish.times(0)
      d.run(default_tag: "test") do
        d.feed(@time, { "a" => "a" * 1000 })
      end
    end
  end

  # Rubocop will erroneously correct the MessagePack.unpack call, for which there's no `unpack1` equivalent method.
  # rubocop:disable Style/UnpackFirst
  sub_test_case "publish" do
    setup do
      @publisher = mock!
      @pubsub_mock = mock!.topic(anything) { @publisher }
      stub(Google::Cloud::Pubsub).new { @pubsub_mock }
    end

    test 'messages are divided into "max_messages"' do
      d = create_driver
      @publisher.publish.times(2)
      d.run(default_tag: "test") do
        # max_messages is default 1000
        1001.times do |i|
          d.feed(@time, { "a" => i })
        end
      end
    end

    test 'messages are divided into "max_total_size"' do
      d = create_driver(%(
        project project-test
        topic topic-test
        key key-test
        max_messages 100000
        max_total_size 1000
      ))

      @publisher.publish.times(2)
      d.run(default_tag: "test") do
        # 400 * 4 / max_total_size = twice
        4.times do
          d.feed(@time, { "a" => "a" * 400 })
        end
      end
    end

    test 'accept "ASCII-8BIT" encoded multibyte strings' do
      # on fluentd v0.14, all strings treated as "ASCII-8BIT" except specified encoding.
      d = create_driver
      @publisher.publish.once
      d.run(default_tag: "test") do
        d.feed(@time, { "a" => "あああ".dup.force_encoding("ASCII-8BIT") })
      end
    end

    test "reraise unexpected errors" do
      d = create_driver
      @publisher.publish.once { raise ReRaisedError }
      assert_raises ReRaisedError do
        d.run(default_tag: "test") do
          d.feed([{ "a" => 1, "b" => 2 }])
        end
      end
    end

    test "reraise RetryableError" do
      d = create_driver
      @publisher.publish.once { raise Google::Cloud::UnavailableError, "TEST" }
      assert_raises Fluent::GcloudPubSub::RetryableError do
        d.run(default_tag: "test") do
          d.feed([{ "a" => 1, "b" => 2 }])
        end
      end
    end

    test "inject section" do
      d = create_driver(%(
        project project-test
        topic topic-test
        key key-test
        <inject>
          tag_key tag
        </inject>
      ))
      @publisher.publish.once
      d.run(default_tag: "test") do
        d.feed({ "foo" => "bar" })
      end
      assert_equal({ "tag" => "test", "foo" => "bar" }, JSON.parse(MessagePack.unpack(d.formatted.first)[0]))
    end

    test "compressed batch" do
      d = create_driver(%(
        project project-test
        topic topic-test
        key key-test
        compress_batches true
        max_messages 2
      ))

      # This is a little hacky: we're doing assertions via matchers.
      # The RR library doesn't seem to provide an easy alternative to this. The
      # downside of this approach is that you will not receive a nice diff if
      # the expectation fails.
      first_batch = [
        '{"foo":"bar"}' + "\n",
        '{"foo":123}' + "\n",
      ]
      @publisher.publish(ZlibCompressedBatch.new(first_batch), { compression_algorithm: "zlib" }).once

      second_batch = [
        '{"msg":"last"}' + "\n",
      ]
      @publisher.publish(ZlibCompressedBatch.new(second_batch), { compression_algorithm: "zlib" }).once

      d.run(default_tag: "test") do
        d.feed({ "foo" => "bar" })
        d.feed({ "foo" => 123 })
        d.feed({ "msg" => "last" })
      end
    end
  end
  # rubocop:enable Style/UnpackFirst
end

private

# A matcher for a compressed batch of messages
# https://www.rubydoc.info/gems/rr/1.2.1/RR/WildcardMatchers
class ZlibCompressedBatch
  attr_reader :expected_messages

  def initialize(expected_messages)
    @expected_messages = expected_messages
  end

  def wildcard_match?(other)
    return true if self == other

    return false unless other.is_a?(String)

    decompressed = Zlib::Inflate.inflate(other)
    other_messages = decompressed.split(30.chr)

    other_messages == expected_messages
  end

  def ==(other)
    other.is_a?(self.class) &&
      other.expected_messages == expected_messages
  end

  alias eql? ==

  def inspect
    "contains compressed messages: #{expected_messages}"
  end
end
