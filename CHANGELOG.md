## ChangeLog

### Release 1.3.3 - 2021/01/05

- Add support for payload compression with `compress_batches`

### Release 1.3.2 - 2019/08/16

- Input plugin
  - Make `topic` parameter optional

### Release 1.3.1 - 2018/06/08

- Input plugin
  - Dumps raw string to logs for parsing errors

### Release 1.3.0 - 2018/05/18

- Make attributes available 

### Release 1.2.0 - 2018/04/24

- Output plugin
  - Support inject section 

### Release 1.1.0 - 2018/03/30

- Output plugin
  - The placeholder is now available in topic param

### Release 1.0.3 - 2018/03/29

- Bump up google-cloud-pubsub to v0.30.x
- Make config file Fluentd v1 compatible

### Release 1.0.2 - 2017/09/11

- Bump up google-cloud-pubsub to v0.27.x

### Release 1.0.1 - 2017/09/05

- Bump up google-cloud-pubsub to v0.26.x

### Release 1.0.0 - 2017/06/23

- Fluentd v0.14 ready
  - Fluentd v0.12 is not supported in the later version

### Release 0.4.6 - 2017/05/14

- Output plugin
  - Make messages exceeding configured size not be published because Pub/Sub clients cannot receive it

### Release 0.4.5 - 2017/04/02

- Bump up google-cloud-pubsub to v0.24.x

### Release 0.4.4 - 2017/03/07

- Bump up google-cloud-pubsub to v0.23.x

### Release 0.4.3 - 2017/02/16

- Input plugin
  - Add "status" method to the http rpc api

### Release 0.4.2 - 2017/02/03

- Make retry to get topic/subscription when Pub/Sub API returns 50x code

### Release 0.4.1 - 2017/02/02

- Bump up google-cloud-pubsub to v0.22.x
- Input plugin
  - Rescue 50x errors on acknowledge api

### Release 0.4.0 - 2017/01/21

- Input plugin
  - Add feature to use record key as tag

### Release 0.3.4 - 2017/01/03

- Output plugin
  - Rescue 50x errors
- Input plugin
  - Guard emit to be called with multi-threading
  - Rescue 50x errors
  - Enabled to select whether to raise an exception if message processing failed

### Release 0.3.3 - 2016/12/03

- Input plugin
  - Fix undefined variable error

### Release 0.3.2 - 2016/11/13

- Add plugin param desc
- Input plugin
  - Improve handling to acknowledge messages

### Release 0.3.1 - 2016/11/03

- Output plugin
  - Improve error handling

### Release 0.3.0 - 2016/10/30

- Bump up google-cloud-pubsub to v0.21
- Input plugin
  - Add multithreaded pulling feature

### Release 0.2.0 - 2016/10/15

- Input plugin
  - Add HTTP RPC feature

### Release 0.1.4 - 2016/09/19

- Input plugin
  - `pull_interval` can be specified float value
  - `topic` must be specified

### Release 0.1.3 - 2016/09/17

- Input plugin
  - Fix error handling and add debug logging

### Release 0.1.2 - 2016/09/11

- Output plugin
  - Change default max message size and add debug message

### Release 0.1.1 - 2016/08/27

- Bump up google-cloud-pubsub (gcloud-ruby) to 0.20

### Release 0.1.0 - 2016/08/22

- Use formatter / parser plugin and add format configuration
- Bump up gcloud-ruby to 0.12
- Remove dependency on lightening buffer
- Fix error caused by Pub/Sub quotas
