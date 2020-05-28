# fluent-plugin-gcloud-pubsub-custom

[![Build Status](https://travis-ci.org/mia-0032/fluent-plugin-gcloud-pubsub-custom.svg?branch=master)](https://travis-ci.org/mia-0032/fluent-plugin-gcloud-pubsub-custom)
[![Gem Version](https://badge.fury.io/rb/fluent-plugin-gcloud-pubsub-custom.svg)](http://badge.fury.io/rb/fluent-plugin-gcloud-pubsub-custom)

This plugin is forked from https://github.com/mdoi/fluent-plugin-gcloud-pubsub

## Overview

[Google Cloud Pub/Sub](https://cloud.google.com/pubsub/) Input/Output(BufferedOutput) plugin for [Fluentd](http://www.fluentd.org/) with [google-cloud](https://googlecloudplatform.github.io/google-cloud-ruby/) gem

- Publish messages to Google Cloud Pub/Sub
- Pull messages from Google Cloud Pub/Sub

## Preparation

- Create a project on Google Developer Console
- Add a topic of Cloud Pub/Sub to the project
- Add a pull style subscription to the topic
- Download your credential (json) or [set scope on GCE instance](https://cloud.google.com/compute/docs/api/how-tos/authorization)

When using output plugin, you need to grant Pub/Sub Publisher and Pub/Sub Viewer role to IAM.

Also, when using input plugin, you need to grant Pub/Sub Subscriber and Pub/Sub Viewer role to IAM.

## Requirements

| fluent-plugin-gcloud-pubsub-custom | fluentd | ruby |
|------------------------|---------|------|
| >= 1.0.0 | >= v0.14.0 | >= 2.1 |
|  < 1.0.0 | >= v0.12.0 | >= 1.9 |

## Installation

Install by gem:

```shell
$ gem install fluent-plugin-gcloud-pubsub-custom
```

**Caution**

This plugin doesn't work in [td-agent](http://docs.fluentd.org/articles/install-by-rpm).

Please use in [Fluentd installed by gem](http://docs.fluentd.org/articles/install-by-gem).

## Configuration

### Publish messages

Use `gcloud_pubsub` output plugin.

```
<match example.publish>
  @type gcloud_pubsub
  project <YOUR PROJECT>
  key <YOUR KEY>
  topic <YOUR TOPIC>
  autocreate_topic false
  max_messages 1000
  max_total_size 9800000
  max_message_size 4000000
  compress_batches false
  <buffer>
    @type memory
    flush_interval 1s
  </buffer>
  <format>
    @type json
  </format>
</match>
```

- `project` (optional)
  - Set your GCP project.
  - Running fluentd on GCP, you don't have to specify.
  - You can also use environment variable such as `GCLOUD_PROJECT`.
- `key` (optional)
  - Set your credential file path.
  - Running fluentd on GCP, you can use scope instead of specifying this.
  - You can also use environment variable such as `GCLOUD_KEYFILE`.
- `topic` (required)
  - Set topic name to publish.
  - You can use placeholder in this param. See: https://docs.fluentd.org/v1.0/articles/buffer-section
- `autocreate_topic` (optional, default: `false`)
  - If set to `true`, specified topic will be created when it doesn't exist.
- `max_messages` (optional, default: `1000`)
  - Publishing messages count per request to Cloud Pub/Sub.
    - See https://cloud.google.com/pubsub/quotas#other_limits
- `max_total_size` (optional, default: `9800000` = `9.8MB`)
  - Publishing messages bytesize per request to Cloud Pub/Sub. This parameter affects only message size. You should specify a little smaller value than quota.
    - See https://cloud.google.com/pubsub/quotas#other_limits
- `max_message_size` (optional, default: `4000000` = `4MB`)
  - Messages exceeding `max_message_size` are not published because Pub/Sub clients cannot receive it.
- `attribute_keys` (optional, default: `[]`)
  - Extract these fields from the record and send them as attributes on the Pub/Sub message. Cannot be set if compress_batches is enabled.
- `metric_prefix` (optional, default: `fluentd_output_gcloud_pubsub`)
  - The prefix for Prometheus metric names
- `compress_batches` (optional, default: `false`)
  - If set to `true`, messages will be batched and compressed before publication. See [message compression](#message-compression) for details.

### Pull messages

Use `gcloud_pubsub` input plugin.

```
<source>
  @type gcloud_pubsub
  tag example.pull
  project <YOUR PROJECT>
  key <YOUR KEY>
  topic <YOUR TOPIC>
  subscription <YOUR SUBSCRIPTION>
  max_messages 1000
  return_immediately true
  pull_interval 0.5
  pull_threads 2
  parse_error_action exception
  enable_rpc true
  rpc_bind 0.0.0.0
  rpc_port 24680
  <parse>
    @type json
  </parse>
</source>
```

- `tag` (required)
  - Set tag of messages.
  - If `tag_key` is specified, `tag` is used as tag when record don't have specified key.
- `tag_key` (optional)
  - Set key to be used as tag.
- `project` (optional)
  - Set your GCP project
  - Running fluentd on GCP, you don't have to specify.
  - You can also use environment variable such as `GCLOUD_PROJECT`.
- `key` (optional)
  - Set your credential file path.
  - Running fluentd on GCP, you can use scope instead of specifying this.
  - You can also use environment variable such as `GCLOUD_KEYFILE`.
- `topic` (optional)
  - Set topic name that the subscription belongs to.
- `subscription` (required)
  - Set subscription name to pull.
- `max_messages` (optional, default: `100`)
  - See maxMessages on https://cloud.google.com/pubsub/docs/reference/rest/v1/projects.subscriptions/pull
- `return_immediately` (optional, default: `true`)
  - See returnImmediately on https://cloud.google.com/pubsub/docs/reference/rest/v1/projects.subscriptions/pull
  - If `return_immediately` is `true` or pulling message is stopped by HTTP RPC, this plugin wait `pull_interval` each pull.
- `pull_interval` (optional, default: `5.0`)
  - Pulling messages by intervals of specified seconds.
- `pull_threads` (optional, default: `1`)
  - Set number of threads to pull messages.
- `attribute_keys` (optional, default: `[]`)
  - Acquire these fields from attributes on the Pub/Sub message and merge them into the record.
- `parse_error_action` (optional, default: `exception`)
  - Set error type when parsing messages fails.
    - `exception`: Raise exception. Messages are not acknowledged.
    - `warning`: Only logging as warning.
- `metric_prefix` (optional, default: `fluentd_input_gcloud_pubsub`)
  - The prefix for Prometheus metric names
- `enable_rpc` (optional, default: `false`)
  - If `true` is specified, HTTP RPC to stop or start pulling message is enabled.
- `rpc_bind` (optional, default: `0.0.0.0`)
  - Bind IP address for HTTP RPC.
- `rpc_port` (optional, default: `24680`)
  - Port for HTTP RPC.

## Message compression

The `compress_batches` option can be used to enable the compression of messages
_before_ publication to Pub/Sub.

This works by collecting the buffered messages, taking up to `max_total_size` or
`max_message_size` input records, then compressing them with Zlib (i.e.
gzip/Deflate) before publishing them as a single message to the Pub/Sub topic.

When transporting large volumes of records via Pub/Sub, e.g. multiple Terabytes
per month, this can lead to significant cost savings, as typically the CPU time
required to compress the messages will be minimal in comparison to the Pub/Sub
costs.

The compression ratio achievable will vary largely depending on the homogeneity
of the input records, but typically will be 50% at the very minimum and often
around 80-90%.

In order to achieve good compression, consider the following:
- Ensure that the buffer is being filled with a reasonable batch of messages: do
  not use `flush_mode immediate`, and keep the `flush_interval` value
  sufficiently high. Use the Prometheus metrics to determine how many records
  are being published per message.
- Keep the `max_messages` and `max_message_size` values high (the defaults are
  optimal).
- If there are many different sources of messages being mixed and routed to a
  single `gcloud_pubsub` output, use multiple outputs (which will each have
  their own buffer) through tagging or [labelling][fluentd-labels].

[fluentd-labels]: https://docs.fluentd.org/quickstart/life-of-a-fluentd-event#labels

The receiving end must be able to decode these compressed batches of messages,
which it can determine via an attribute set on the Pub/Sub message. The
`gcloud_pubsub` input plugin will do this transparently, decompressing any
messages which contain a batch of records and normally processing any messages
which represent just a single record.
Therefore, as long as all of the receivers are updated with support for
compressed batches first, it's then possible to gradually roll out this feature.

## Prometheus metrics

The input and output plugins expose several metrics in order to monitor
performance:

- `fluentd_output_gcloud_pubsub_compression_enabled`
  - Gauge: Whether compression/batching is enabled
- `fluentd_output_gcloud_pubsub_messages_published_per_batch`
  - Histogram: Number of records published to Pub/Sub per buffer flush
- `fluentd_output_gcloud_pubsub_messages_published_bytes`
  - Histogram: Total size in bytes of the records published to Pub/Sub,
    **before** compression.
- `fluentd_output_gcloud_pubsub_messages_compression_duration_seconds`
  - Histogram: Time taken to compress a batch of messages
- `fluentd_output_gcloud_pubsub_messages_compressed_size_per_original_size_ratio`
  - Histogram: Compression ratio achieved on a batch of messages, expressed in
    terms of space saved.

- `fluentd_input_gcloud_pubsub_pull_errors_total`
  - Counter: Errors encountered while pulling or processing messages (split by a
    `retryable` label)
- `fluentd_input_gcloud_pubsub_messages_pulled`
  - Histogram: Number of Pub/Sub messages pulled by the subscriber on each invocation
- `fluentd_input_gcloud_pubsub_messages_pulled_bytes`
  - Histogram: Total size in bytes of the Pub/Sub messages pulled by the subscriber on each invocation

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## TODO

- Add `tag` attribute in output plugin and use `tag` attribute as tag in input plugin.
- Send ack after other output plugin committed (if possible).

## Authors

- [@mdoi](https://github.com/mdoi) : First author
- [@mia-0032](https://github.com/mia-0032) : This version author
