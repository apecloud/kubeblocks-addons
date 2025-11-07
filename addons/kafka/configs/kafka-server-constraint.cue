//Copyright (C) 2022-2023 ApeCloud Co., Ltd
//
//This file is part of KubeBlocks project
//
//This program is free software: you can redistribute it and/or modify
//it under the terms of the GNU Affero General Public License as published by
//the Free Software Foundation, either version 3 of the License, or
//(at your option) any later version.
//
//This program is distributed in the hope that it will be useful
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU Affero General Public License for more details.
//
//You should have received a copy of the GNU Affero General Public License
//along with this program.  If not, see <http://www.gnu.org/licenses/>.

// https://kafka.apache.org/documentation/#brokerconfigs
// build from kafka:3.3.2 clients/src/main/java/org/apache/kafka/common/config/ConfigDef.java
#KafkaParameter: {

	"allow.everyone.if.no.acl.found"?: bool | *true

  // Enable auto creation of topic on the server
  "auto.create.topics.enable"?: bool | *true

  // Enables auto leader balancing. A background thread checks the distribution of partition leaders at regular intervals, configurable by `leader.imbalance.check.interval.seconds`. If the leader   imbalance exceeds `leader.imbalance.per.broker.percentage`, leader rebalance to the preferred leader for partitions is triggered.
  "auto.leader.rebalance.enable"?: bool | *true

  // The number of threads to use for various background processing tasks
  "background.threads"?: int & >=1 | *10

  // Specify the final compression type for a given topic. This configuration accepts the standard compression codecs ('gzip', 'snappy', 'lz4', 'zstd'). It additionally accepts 'uncompressed' which is   equivalent to no compression; and 'producer' which means retain the original compression codec set by the producer.
  "compression.type"?: string & "uncompressed" | "zstd" | "lz4" | "snappy" | "gzip" | "producer" | *"producer"

  // Maximum time in milliseconds before starting new elections. This is used in the binary exponential backoff mechanism that helps prevent gridlocked elections
  "controller.quorum.election.backoff.max.ms"?: int | *1000

  // Maximum time in milliseconds to wait without being able to fetch from the leader before triggering a new election
  "controller.quorum.election.timeout.ms"?: int | *1000

  // Maximum time without a successful fetch from the current leader before becoming a candidate and triggering an election for voters; Maximum time without receiving fetch from a majority of the   quorum before asking around to see if there's a new epoch for leader
  "controller.quorum.fetch.timeout.ms"?: int | *2000

  // Enables delete topic. Delete topic through the admin tool will have no effect if this config is turned off
  "delete.topic.enable"?: bool | *false

  // A comma-separated list of listener names which may be started before the authorizer has finished initialization. This is useful when the authorizer is dependent on the cluster itself for   bootstrapping, as is the case for the StandardAuthorizer (which stores ACLs in the metadata log.) By default, all listeners included in controller.listener.names will also be early start listeners. A   listener should not appear in this list if it accepts external traffic.
  "early.start.listeners"?: string

  // The frequency with which the partition rebalance check is triggered by the controller
  "leader.imbalance.check.interval.seconds"?: int & >=1 | *300

  // The ratio of leader imbalance allowed per broker. The controller would trigger a leader balance if it goes above this value per broker. The value is specified in percentage.
  "leader.imbalance.per.broker.percentage"?: int | *10

  // The number of messages accumulated on a log partition before messages are flushed to disk
  "log.flush.interval.messages"?: int & >=1 | *9223372036854775807

  // The maximum time in ms that a message in any topic is kept in memory before flushed to disk. If not set, the value in log.flush.scheduler.interval.ms is used
  "log.flush.interval.ms"?: int

  // The frequency with which we update the persistent record of the last flush which acts as the log recovery point
  "log.flush.offset.checkpoint.interval.ms"?: int & >=0 | *60000

  // The frequency in ms that the log flusher checks whether any log needs to be flushed to disk
  "log.flush.scheduler.interval.ms"?: int | *9223372036854775807

  // The frequency with which we update the persistent record of log start offset
  "log.flush.start.offset.checkpoint.interval.ms"?: int & >=0 | *60000

  // The maximum size of the log before deleting it
  "log.retention.bytes"?: int | *-1

  // The number of hours to keep a log file before deleting it (in hours), tertiary to log.retention.ms property
  "log.retention.hours"?: int | *168

  // The number of minutes to keep a log file before deleting it (in minutes), secondary to log.retention.ms property. If not set, the value in log.retention.hours is used
  "log.retention.minutes"?: int

  // The number of milliseconds to keep a log file before deleting it (in milliseconds), If not set, the value in log.retention.minutes is used. If set to -1, no time limit is applied.
  "log.retention.ms"?: int

  // The maximum time before a new log segment is rolled out (in hours), secondary to log.roll.ms property
  "log.roll.hours"?: int & >=1 | *168

  // The maximum jitter to subtract from logRollTimeMillis (in hours), secondary to log.roll.jitter.ms property
  "log.roll.jitter.hours"?: int & >=0 | *0

  // The maximum jitter to subtract from logRollTimeMillis (in milliseconds). If not set, the value in log.roll.jitter.hours is used
  "log.roll.jitter.ms"?: int

  // The maximum time before a new log segment is rolled out (in milliseconds). If not set, the value in log.roll.hours is used
  "log.roll.ms"?: int

  // The maximum size of a single log file
  "log.segment.bytes"?: int & >=14 | *1073741824

  // The amount of time to wait before deleting a file from the filesystem
  "log.segment.delete.delay.ms"?: int & >=0 | *60000

  // The largest record batch size allowed by Kafka (after compression if compression is enabled). If this is increased and there are consumers older than 0.10.2, the consumers' fetch size must also be   increased so that they can fetch record batches this large. In the latest message format version, records are always grouped into batches for efficiency. In previous message format versions,   uncompressed records are not grouped into batches and this limit only applies to a single record in that case.This can be set per topic with the topic level <code>max.message.bytes</code> config.
  "message.max.bytes"?: int & >=0 | *1048588

  // This is the maximum number of bytes in the log between the latest snapshot and the high-watermark needed before generating a new snapshot.
  "metadata.log.max.record.bytes.between.snapshots"?: int & >=1 | *20971520

  // The maximum size of a single metadata log file.
  "metadata.log.segment.bytes"?: int & >=12 | *1073741824

  // The maximum time before a new metadata log file is rolled out (in milliseconds).
  "metadata.log.segment.ms"?: int | *604800000

  // The maximum combined size of the metadata log and snapshots before deleting old snapshots and log files. Since at least one snapshot must exist before any logs can be deleted, this is a soft limit.
  "metadata.max.retention.bytes"?: int | *-1

  // The number of milliseconds to keep a metadata log file or snapshot before deleting it. Since at least one snapshot must exist before any logs can be deleted, this is a soft limit.
  "metadata.max.retention.ms"?: int | *604800000

  // When a producer sets acks to "all" (or "-1"), min.insync.replicas specifies the minimum number of replicas that must acknowledge a write for the write to be considered successful. If this minimum   cannot be met, then the producer will raise an exception (either NotEnoughReplicas or NotEnoughReplicasAfterAppend).<br>When used together, min.insync.replicas and acks allow you to enforce greater   durability guarantees. A typical scenario would be to create a topic with a replication factor of 3, set min.insync.replicas to 2, and produce with acks of "all". This will ensure that the producer   raises an exception if a majority of replicas do not receive a write.
  "min.insync.replicas"?: int & >=1 | *1

  // The number of threads that the server uses for processing requests, which may include disk I/O
  "num.io.threads"?: int & >=1 | *8

  // The number of threads that the server uses for receiving requests from the network and sending responses to the network
  "num.network.threads"?: int & >=1 | *3

  // The number of threads per data directory to be used for log recovery at startup and flushing at shutdown
  "num.recovery.threads.per.data.dir"?: int & >=1 | *1

  // The number of threads that can move replicas between log directories, which may include disk I/O
  "num.replica.alter.log.dirs.threads"?: int

  // Number of fetcher threads used to replicate records from each source broker. The total number of fetchers on each broker is bound by <code>num.replica.fetchers</code> multiplied by the number of   brokers in the cluster.Increasing this value can increase the degree of I/O parallelism in the follower and leader broker at the cost of higher CPU and memory utilization.
  "num.replica.fetchers"?: int | *1

  // The maximum size for a metadata entry associated with an offset commit
  "offset.metadata.max.bytes"?: int | *4096

  // The required acks before the commit can be accepted. In general, the default (-1) should not be overridden
  "offsets.commit.required.acks"?: int | *-1

  // Offset commit will be delayed until all replicas for the offsets topic receive the commit or this timeout is reached. This is similar to the producer request timeout.
  "offsets.commit.timeout.ms"?: int & >=1 | *5000

  // Batch size for reading from the offsets segments when loading offsets into the cache (soft-limit, overridden if records are too large).
  "offsets.load.buffer.size"?: int & >=1 | *5242880

  // Frequency at which to check for stale offsets
  "offsets.retention.check.interval.ms"?: int & >=1 | *600000

  // After a consumer group loses all its consumers (i.e. becomes empty) its offsets will be kept for this retention period before getting discarded. For standalone consumers (using manual assignment),   offsets will be expired after the time of last commit plus this retention period.
  "offsets.retention.minutes"?: int & >=1 | *10080

  // Compression codec for the offsets topic - compression may be used to achieve "atomic" commits
  "offsets.topic.compression.codec"?: int | *0

  // The number of partitions for the offset commit topic (should not change after deployment)
  "offsets.topic.num.partitions"?: int & >=1 | *50

  // The replication factor for the offsets topic (set higher to ensure availability). Internal topic creation will fail until the cluster size meets this replication factor requirement.
  "offsets.topic.replication.factor"?: int & >=1 | *3

  // The offsets topic segment bytes should be kept relatively small in order to facilitate faster log compaction and cache loads
  "offsets.topic.segment.bytes"?: int & >=1 | *104857600

  // The number of queued requests allowed for data-plane, before blocking the network threads
  "queued.max.requests"?: int & >=1 | *500

  // Minimum bytes expected for each fetch response. If not enough bytes, wait up to <code>replica.fetch.wait.max.ms</code> (broker config).
  "replica.fetch.min.bytes"?: int | *1

  // The maximum wait time for each fetcher request issued by follower replicas. This value should always be less than the replica.lag.time.max.ms at all times to prevent frequent shrinking of ISR for   low throughput topics
  "replica.fetch.wait.max.ms"?: int | *500

  // The frequency with which the high watermark is saved out to disk
  "replica.high.watermark.checkpoint.interval.ms"?: int | *5000

  // If a follower hasn't sent any fetch requests or hasn't consumed up to the leaders log end offset for at least this time, the leader will remove the follower from isr
  "replica.lag.time.max.ms"?: int | *30000

  // The socket receive buffer for network requests
  "replica.socket.receive.buffer.bytes"?: int | *65536

  // The socket timeout for network requests. Its value should be at least replica.fetch.wait.max.ms
  "replica.socket.timeout.ms"?: int | *30000

  // The configuration controls the maximum amount of time the client will wait for the response of a request. If the response is not received before the timeout elapses the client will resend the   request if necessary or fail the request if retries are exhausted.
  "request.timeout.ms"?: int | *30000

  // SASL mechanism used for communication with controllers. Default is GSSAPI.
  "sasl.mechanism.controller.protocol"?: string | *"GSSAPI"

  // The SO_RCVBUF buffer of the socket server sockets. If the value is -1, the OS default will be used.
  "socket.receive.buffer.bytes"?: int | *102400

  // The maximum number of bytes in a socket request
  "socket.request.max.bytes"?: int & >=1 | *104857600

  // The SO_SNDBUF buffer of the socket server sockets. If the value is -1, the OS default will be used.
  "socket.send.buffer.bytes"?: int | *102400

  // The maximum allowed timeout for transactions. If a client’s requested transaction time exceed this, then the broker will return an error in InitProducerIdRequest. This prevents a client from too   large of a timeout, which can stall consumers reading from topics included in the transaction.
  "transaction.max.timeout.ms"?: int & >=1 | *900000

  // Batch size for reading from the transaction log segments when loading producer ids and transactions into the cache (soft-limit, overridden if records are too large).
  "transaction.state.log.load.buffer.size"?: int & >=1 | *5242880

  // Overridden min.insync.replicas config for the transaction topic.
  "transaction.state.log.min.isr"?: int & >=1 | *2

  // The number of partitions for the transaction topic (should not change after deployment).
  "transaction.state.log.num.partitions"?: int & >=1 | *50

  // The replication factor for the transaction topic (set higher to ensure availability). Internal topic creation will fail until the cluster size meets this replication factor requirement.
  "transaction.state.log.replication.factor"?: int & >=1 | *3

  // The transaction topic segment bytes should be kept relatively small in order to facilitate faster log compaction and cache loads
  "transaction.state.log.segment.bytes"?: int & >=1 | *104857600

  // The time in ms that the transaction coordinator will wait without receiving any transaction status updates for the current transaction before expiring its transactional id. This setting also   influences producer id expiration - producer ids are expired once this time has elapsed after the last write with the given producer id. Note that producer ids may expire sooner if the last write   from the producer id is deleted due to the topic's retention settings.
  "transactional.id.expiration.ms"?: int & >=1 | *604800000

  // Indicates whether to enable replicas not in the ISR set to be elected as leader as a last resort, even though doing so may result in data loss
  "unclean.leader.election.enable"?: bool | *false

  // Specifies the ZooKeeper connection string in the form <code>hostname:port</code> where host and port are the host and port of a ZooKeeper server. To allow connecting through other ZooKeeper nodes   when that ZooKeeper machine is down you can also specify multiple hosts in the form <code>hostname1:port1,hostname2:port2,hostname3:port3</code>.
  // The server can also have a ZooKeeper chroot path as part of its ZooKeeper connection string which puts its data under some path in the global ZooKeeper namespace. For example to give a chroot path   of <code>/chroot/path</code> you would give the connection string as <code>hostname1:port1,hostname2:port2,hostname3:port3/chroot/path</code>.
  "zookeeper.connect"?: string

  // The max time that the client waits to establish a connection to zookeeper. If not set, the value in zookeeper.session.timeout.ms is used
  "zookeeper.connection.timeout.ms"?: int

  // The maximum number of unacknowledged requests the client will send to Zookeeper before blocking.
  "zookeeper.max.in.flight.requests"?: int & >=1 | *10

  // Zookeeper session timeout
  "zookeeper.session.timeout.ms"?: int | *18000

  // Set client to use secure ACLs
  "zookeeper.set.acl"?: bool | *false

  // The length of time in milliseconds between broker heartbeats. Used when running in KRaft mode.
  "broker.heartbeat.interval.ms"?: int | *2000

  // Enable automatic broker id generation on the server. When enabled the value configured for reserved.broker.max.id should be reviewed.
  "broker.id.generation.enable"?: bool | *true

  // Rack of the broker. This will be used in rack aware replication assignment for fault tolerance. Examples: `RACK1`, `us-east-1d`
  "broker.rack"?: string

  // The length of time in milliseconds that a broker lease lasts if no heartbeats are made. Used when running in KRaft mode.
  "broker.session.timeout.ms"?: int | *9000

  // Idle connections timeout: the server socket processor threads close the connections that idle more than this
  "connections.max.idle.ms"?: int | *600000

  // When explicitly set to a positive number (the default is 0, not a positive number), a session lifetime that will not exceed the configured value will be communicated to v2.2.0 or later clients   when they authenticate. The broker will disconnect any such connection that is not re-authenticated within the session lifetime and that is then subsequently used for any purpose other than   re-authentication. Configuration names can optionally be prefixed with listener prefix and SASL mechanism name in lower-case. For example,   listener.name.sasl_ssl.oauthbearer.connections.max.reauth.ms=3600000
  "connections.max.reauth.ms"?: int | *0

  // Enable controlled shutdown of the server
  "controlled.shutdown.enable"?: bool | *true

  // Controlled shutdown can fail for multiple reasons. This determines the number of retries when such failure happens
  "controlled.shutdown.max.retries"?: int | *3

  // Before each retry, the system needs time to recover from the state that caused the previous failure (Controller fail over, replica lag etc). This config determines the amount of time to wait   before retrying.
  "controlled.shutdown.retry.backoff.ms"?: int | *5000

  // The duration in milliseconds that the leader will wait for writes to accumulate before flushing them to disk.
  "controller.quorum.append.linger.ms"?: int | *25

  // The configuration controls the maximum amount of time the client will wait for the response of a request. If the response is not received before the timeout elapses the client will resend the   request if necessary or fail the request if retries are exhausted.
  "controller.quorum.request.timeout.ms"?: int | *2000

  // The socket timeout for controller-to-broker channels
  "controller.socket.timeout.ms"?: int | *30000

  // The default replication factors for automatically created topics
  "default.replication.factor"?: int | *1

  // The token validity time in miliseconds before the token needs to be renewed. Default value 1 day.
  "delegation.token.expiry.time.ms"?: int & >=1 | *86400000

  // DEPRECATED: An alias for delegation.token.secret.key, which should be used instead of this config.
  "delegation.token.master.key"?: string

  // The token has a maximum lifetime beyond which it cannot be renewed anymore. Default value 7 days.
  "delegation.token.max.lifetime.ms"?: int & >=1 | *604800000

  // Secret key to generate and verify delegation tokens. The same key must be configured across all the brokers.  If the key is not set or set to empty string, brokers will disable the delegation   token support.
  "delegation.token.secret.key"?: string

  // The purge interval (in number of requests) of the delete records request purgatory
  "delete.records.purgatory.purge.interval.requests"?: int | *1

  // The maximum number of bytes we will return for a fetch request. Must be at least 1024.
  "fetch.max.bytes"?: int & >=1024 | *57671680

  // The purge interval (in number of requests) of the fetch request purgatory
  "fetch.purgatory.purge.interval.requests"?: int | *1000

  // The amount of time the group coordinator will wait for more consumers to join a new group before performing the first rebalance. A longer delay means potentially fewer rebalances, but increases   the time until processing begins.
  "group.initial.rebalance.delay.ms"?: int | *3000

  // The maximum allowed session timeout for registered consumers. Longer timeouts give consumers more time to process messages in between heartbeats at the cost of a longer time to detect failures.
  "group.max.session.timeout.ms"?: int | *1800000

  // The maximum number of consumers that a single consumer group can accommodate.
  "group.max.size"?: int & >=1 | *2147483647

  // The minimum allowed session timeout for registered consumers. Shorter timeouts result in quicker failure detection at the cost of more frequent consumer heartbeating, which can overwhelm broker   resources.
  "group.min.session.timeout.ms"?: int | *6000

  // When initially registering with the controller quorum, the number of milliseconds to wait before declaring failure and exiting the broker process.
  "initial.broker.registration.timeout.ms"?: int | *60000

  // Specify which version of the inter-broker protocol will be used.
  //  This is typically bumped after all brokers were upgraded to a new version.
  //  Example of some valid values are: 0.8.0, 0.8.1, 0.8.1.1, 0.8.2, 0.8.2.0, 0.8.2.1, 0.9.0.0, 0.9.0.1 Check MetadataVersion for the full list.
  "inter.broker.protocol.version"?: string & "0.8.0" | "0.8.1" | "0.8.2" | "0.9.0" | "0.10.0-IV0" | "0.10.0-IV1" | "0.10.1-IV0" | "0.10.1-IV1" | "0.10.1-IV2" | "0.10.2-IV0" | "0.11.0-IV0" |   "0.11.0-IV1" | "0.11.0-IV2" | "1.0-IV0" | "1.1-IV0" | "2.0-IV0" | "2.0-IV1" | "2.1-IV0" | "2.1-IV1" | "2.1-IV2" | "2.2-IV0" | "2.2-IV1" | "2.3-IV0" | "2.3-IV1" | "2.4-IV0" | "2.4-IV1" | "2.5-IV0" |   "2.6-IV0" | "2.7-IV0" | "2.7-IV1" | "2.7-IV2" | "2.8-IV0" | "2.8-IV1" | "3.0-IV0" | "3.0-IV1" | "3.1-IV0" | "3.2-IV0" | "3.3-IV0" | "3.3-IV1" | "3.3-IV2" | "3.3-IV3" | *"3.3-IV3"

  // The amount of time to sleep when there are no logs to clean
  "log.cleaner.backoff.ms"?: int & >=0 | *15000

  // The total memory used for log deduplication across all cleaner threads
  "log.cleaner.dedupe.buffer.size"?: int | *134217728

  // The amount of time to retain delete tombstone markers for log compacted topics. This setting also gives a bound on the time in which a consumer must complete a read if they begin from offset 0 to   ensure that they get a valid snapshot of the final stage (otherwise delete tombstones may be collected before they complete their scan).
  "log.cleaner.delete.retention.ms"?: int & >=0 | *86400000

  // Enable the log cleaner process to run on the server. Should be enabled if using any topics with a cleanup.policy=compact including the internal offsets topic. If disabled those topics will not be   compacted and continually grow in size.
  "log.cleaner.enable"?: bool | *true

  // Log cleaner dedupe buffer load factor. The percentage full the dedupe buffer can become. A higher value will allow more log to be cleaned at once but will lead to more hash collisions
  "log.cleaner.io.buffer.load.factor"?: number | *0.9

  // The total memory used for log cleaner I/O buffers across all cleaner threads
  "log.cleaner.io.buffer.size"?: int & >=0 | *524288

  // The log cleaner will be throttled so that the sum of its read and write i/o will be less than this value on average
  "log.cleaner.io.max.bytes.per.second"?: number | *1.7976931348623157E308

  // The maximum time a message will remain ineligible for compaction in the log. Only applicable for logs that are being compacted.
  "log.cleaner.max.compaction.lag.ms"?: int & >=1 | *9223372036854775807

  // The minimum ratio of dirty log to total log for a log to eligible for cleaning. If the log.cleaner.max.compaction.lag.ms or the log.cleaner.min.compaction.lag.ms configurations are also specified,   then the log compactor considers the log eligible for compaction as soon as either: (i) the dirty ratio threshold has been met and the log has had dirty (uncompacted) records for at least the   log.cleaner.min.compaction.lag.ms duration, or (ii) if the log has had dirty (uncompacted) records for at most the log.cleaner.max.compaction.lag.ms period.
  "log.cleaner.min.cleanable.ratio"?: number & >=0 & <=1 | *0.5

  // The minimum time a message will remain uncompacted in the log. Only applicable for logs that are being compacted.
  "log.cleaner.min.compaction.lag.ms"?: int & >=0 | *0

  // The number of background threads to use for log cleaning
  "log.cleaner.threads"?: int & >=0 | *1

  // The default cleanup policy for segments beyond the retention window. A comma separated list of valid policies. Valid policies are: "delete" and "compact"
  "log.cleanup.policy"?: string & "compact" | "delete" | *"delete"

  // The interval with which we add an entry to the offset index
  "log.index.interval.bytes"?: int & >=0 | *4096

  // The maximum size in bytes of the offset index
  "log.index.size.max.bytes"?: int & >=4 | *10485760

  // Specify the message format version the broker will use to append messages to the logs. The value should be a valid MetadataVersion. Some examples are: 0.8.2, 0.9.0.0, 0.10.0, check MetadataVersion   for more details. By setting a particular message format version, the user is certifying that all the existing messages on disk are smaller or equal than the specified version. Setting this value   incorrectly will cause consumers with older versions to break as they will receive messages with a format that they don't understand.
  "log.message.format.version"?: string & "0.8.0" | "0.8.1" | "0.8.2" | "0.9.0" | "0.10.0-IV0" | "0.10.0-IV1" | "0.10.1-IV0" | "0.10.1-IV1" | "0.10.1-IV2" | "0.10.2-IV0" | "0.11.0-IV0" | "0.11.0-IV1" |   "0.11.0-IV2" | "1.0-IV0" | "1.1-IV0" | "2.0-IV0" | "2.0-IV1" | "2.1-IV0" | "2.1-IV1" | "2.1-IV2" | "2.2-IV0" | "2.2-IV1" | "2.3-IV0" | "2.3-IV1" | "2.4-IV0" | "2.4-IV1" | "2.5-IV0" | "2.6-IV0" |   "2.7-IV0" | "2.7-IV1" | "2.7-IV2" | "2.8-IV0" | "2.8-IV1" | "3.0-IV0" | "3.0-IV1" | "3.1-IV0" | "3.2-IV0" | "3.3-IV0" | "3.3-IV1" | "3.3-IV2" | "3.3-IV3" | *"3.0-IV1"

  // The maximum difference allowed between the timestamp when a broker receives a message and the timestamp specified in the message. If log.message.timestamp.type=CreateTime, a message will be   rejected if the difference in timestamp exceeds this threshold. This configuration is ignored if log.message.timestamp.type=LogAppendTime.The maximum timestamp difference allowed should be no greater   than log.retention.ms to avoid unnecessarily frequent log rolling.
  "log.message.timestamp.difference.max.ms"?: int & >=0 | *9223372036854775807

  // Define whether the timestamp in the message is message create time or log append time. The value should be either `CreateTime` or `LogAppendTime`
  "log.message.timestamp.type"?: string & "CreateTime" | "LogAppendTime" | *"CreateTime"

  // Should pre allocate file when create new segment? If you are using Kafka on Windows, you probably need to set it to true.
  "log.preallocate"?: bool | *false

  // The frequency in milliseconds that the log cleaner checks whether any log is eligible for deletion
  "log.retention.check.interval.ms"?: int & >=1 | *300000

  // The maximum connection creation rate we allow in the broker at any time. Listener-level limits may also be configured by prefixing the config name with the listener prefix, for example, <code>  listener.name.internal.max.connection.creation.rate</code>.Broker-wide connection rate limit should be configured based on broker capacity while listener limits should be configured based on   application requirements. New connections will be throttled if either the listener or the broker limit is reached, with the exception of inter-broker listener. Connections on the inter-broker   listener will be throttled only when the listener-level rate limit is reached.
  "max.connection.creation.rate"?: int & >=0 | *2147483647

  // The maximum number of connections we allow in the broker at any time. This limit is applied in addition to any per-ip limits configured using max.connections.per.ip. Listener-level limits may also   be configured by prefixing the config name with the listener prefix, for example, <code>listener.name.internal.max.connections</code>. Broker-wide limit should be configured based on broker capacity   while listener limits should be configured based on application requirements. New connections are blocked if either the listener or broker limit is reached. Connections on the inter-broker listener   are permitted even if broker-wide limit is reached. The least recently used connection on another listener will be closed in this case.
  "max.connections"?: int & >=0 | *2147483647

  // The maximum number of connections we allow from each ip address. This can be set to 0 if there are overrides configured using max.connections.per.ip.overrides property. New connections from the ip   address are dropped if the limit is reached.
  "max.connections.per.ip"?: int & >=0 | *2147483647

  // A comma-separated list of per-ip or hostname overrides to the default maximum number of connections. An example value is "hostName:100,127.0.0.1:200"
  "max.connections.per.ip.overrides"?: string | *""

  // The maximum number of incremental fetch sessions that we will maintain.
  "max.incremental.fetch.session.cache.slots"?: int & >=0 | *1000

  // The default number of log partitions per topic
  "num.partitions"?: int & >=1 | *1

  // The old secret that was used for encoding dynamically configured passwords. This is required only when the secret is updated. If specified, all dynamically encoded passwords are decoded using this   old secret and re-encoded using password.encoder.secret when broker starts up.
  "password.encoder.old.secret"?: string

  // The secret used for encoding dynamically configured passwords for this broker.
  "password.encoder.secret"?: string

  // The fully qualified name of a class that implements the KafkaPrincipalBuilder interface, which is used to build the KafkaPrincipal object used during authorization. If no principal builder is   defined, the default behavior depends on the security protocol in use. For SSL authentication,  the principal will be derived using the rules defined by <code>ssl.principal.mapping.rules</code>   applied on the distinguished name from the client certificate if one is provided; otherwise, if client authentication is not required, the principal name will be ANONYMOUS. For SASL authentication,   the principal will be derived using the rules defined by <code>sasl.kerberos.principal.to.local.rules</code> if GSSAPI is in use, and the SASL authentication ID for other mechanisms. For PLAINTEXT,   the principal will be ANONYMOUS.
  "principal.builder.class"?: string | *"org.apache.kafka.common.security.authenticator.DefaultKafkaPrincipalBuilder"

  // The purge interval (in number of requests) of the producer request purgatory
  "producer.purgatory.purge.interval.requests"?: int | *1000

  // The number of queued bytes allowed before no more requests are read
  "queued.max.request.bytes"?: int | *-1

  // The amount of time to sleep when fetch partition error occurs.
  "replica.fetch.backoff.ms"?: int & >=0 | *1000

  // The number of bytes of messages to attempt to fetch for each partition. This is not an absolute maximum, if the first record batch in the first non-empty partition of the fetch is larger than this   value, the record batch will still be returned to ensure that progress can be made. The maximum record batch size accepted by the broker is defined via <code>message.max.bytes</code> (broker config)   or <code>max.message.bytes</code> (topic config).
  "replica.fetch.max.bytes"?: int & >=0 | *1048576

  // Maximum bytes expected for the entire fetch response. Records are fetched in batches, and if the first record batch in the first non-empty partition of the fetch is larger than this value, the   record batch will still be returned to ensure that progress can be made. As such, this is not an absolute maximum. The maximum record batch size accepted by the broker is defined via <code>  message.max.bytes</code> (broker config) or <code>max.message.bytes</code> (topic config).
  "replica.fetch.response.max.bytes"?: int & >=0 | *10485760

  // The fully qualified class name that implements ReplicaSelector. This is used by the broker to find the preferred read replica. By default, we use an implementation that returns the leader.
  "replica.selector.class"?: string

  // Max number that can be used for a broker.id
  "reserved.broker.max.id"?: int & >=0 | *1000

  // The fully qualified name of a SASL client callback handler class that implements the AuthenticateCallbackHandler interface.
  "sasl.client.callback.handler.class"?: string

  // The list of SASL mechanisms enabled in the Kafka server. The list may contain any mechanism for which a security provider is available. Only GSSAPI is enabled by default.
  "sasl.enabled.mechanisms"?: string | *"GSSAPI"

  // JAAS login context parameters for SASL connections in the format used by JAAS configuration files. JAAS configuration file format is described <a href="http://docs.oracle.com/javase/8/docs/  technotes/guides/security/jgss/tutorials/LoginConfigFile.html">here</a>. The format for the value is: <code>loginModuleClass controlFlag (optionName=optionValue)*;</code>. For brokers, the config   must be prefixed with listener prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.jaas.config=com.example.ScramLoginModule required;
  "sasl.jaas.config"?: string

  // Kerberos kinit command path.
  "sasl.kerberos.kinit.cmd"?: string | *"/usr/bin/kinit"

  // Login thread sleep time between refresh attempts.
  "sasl.kerberos.min.time.before.relogin"?: int | *60000

  // A list of rules for mapping from principal names to short names (typically operating system usernames). The rules are evaluated in order and the first rule that matches a principal name is used to   map it to a short name. Any later rules in the list are ignored. By default, principal names of the form {username}/{hostname}@{REALM} are mapped to {username}. For more details on the format please   see <a href="#security_authz"> security authorization and acls</a>. Note that this configuration is ignored if an extension of KafkaPrincipalBuilder is provided by the <code>  principal.builder.class</code> configuration.
  "sasl.kerberos.principal.to.local.rules"?: string | *"DEFAULT"

  // The Kerberos principal name that Kafka runs as. This can be defined either in Kafka's JAAS config or in Kafka's config.
  "sasl.kerberos.service.name"?: string

  // Percentage of random jitter added to the renewal time.
  "sasl.kerberos.ticket.renew.jitter"?: number | *0.05

  // Login thread will sleep until the specified window factor of time from last refresh to ticket's expiry has been reached, at which time it will try to renew the ticket.
  "sasl.kerberos.ticket.renew.window.factor"?: number | *0.8

  // The fully qualified name of a SASL login callback handler class that implements the AuthenticateCallbackHandler interface. For brokers, login callback handler config must be prefixed with listener   prefix and SASL mechanism name in lower-case. For example, listener.name.sasl_ssl.scram-sha-256.sasl.login.callback.handler.class=com.example.CustomScramLoginCallbackHandler
  "sasl.login.callback.handler.class"?: string

  // The fully qualified name of a class that implements the Login interface. For brokers, login config must be prefixed with listener prefix and SASL mechanism name in lower-case. For example,   listener.name.sasl_ssl.scram-sha-256.sasl.login.class=com.example.CustomScramLogin
  "sasl.login.class"?: string

  // The amount of buffer time before credential expiration to maintain when refreshing a credential, in seconds. If a refresh would otherwise occur closer to expiration than the number of buffer   seconds then the refresh will be moved up to maintain as much of the buffer time as possible. Legal values are between 0 and 3600 (1 hour); a default value of  300 (5 minutes) is used if no value is   specified. This value and sasl.login.refresh.min.period.seconds are both ignored if their sum exceeds the remaining lifetime of a credential. Currently applies only to OAUTHBEARER.
  "sasl.login.refresh.buffer.seconds"?: int | *300

  // The desired minimum time for the login refresh thread to wait before refreshing a credential, in seconds. Legal values are between 0 and 900 (15 minutes); a default value of 60 (1 minute) is used   if no value is specified.  This value and  sasl.login.refresh.buffer.seconds are both ignored if their sum exceeds the remaining lifetime of a credential. Currently applies only to OAUTHBEARER.
  "sasl.login.refresh.min.period.seconds"?: int | *60

  // Login refresh thread will sleep until the specified window factor relative to the credential's lifetime has been reached, at which time it will try to refresh the credential. Legal values are   between 0.5 (50%) and 1.0 (100%) inclusive; a default value of 0.8 (80%) is used if no value is specified. Currently applies only to OAUTHBEARER.
  "sasl.login.refresh.window.factor"?: number | *0.8

  // The maximum amount of random jitter relative to the credential's lifetime that is added to the login refresh thread's sleep time. Legal values are between 0 and 0.25 (25%) inclusive; a default   value of 0.05 (5%) is used if no value is specified. Currently applies only to OAUTHBEARER.
  "sasl.login.refresh.window.jitter"?: number | *0.05

  // SASL mechanism used for inter-broker communication. Default is GSSAPI.
  "sasl.mechanism.inter.broker.protocol"?: string | *"GSSAPI"

  // The OAuth/OIDC provider URL from which the provider's <a href="https://datatracker.ietf.org/doc/html/rfc7517#section-5">JWKS (JSON Web Key Set)</a> can be retrieved. The URL can be HTTP(S)-based   or file-based. If the URL is HTTP(S)-based, the JWKS data will be retrieved from the OAuth/OIDC provider via the configured URL on broker startup. All then-current keys will be cached on the broker   for incoming requests. If an authentication request is received for a JWT that includes a "kid" header claim value that isn't yet in the cache, the JWKS endpoint will be queried again on demand.   However, the broker polls the URL every sasl.oauthbearer.jwks.endpoint.refresh.ms milliseconds to refresh the cache with any forthcoming keys before any JWT requests that include them are received.   If the URL is file-based, the broker will load the JWKS file from a configured location on startup. In the event that the JWT includes a "kid" header value that isn't in the JWKS file, the broker   will reject the JWT and authentication will fail.
  "sasl.oauthbearer.jwks.endpoint.url"?: string

  // The URL for the OAuth/OIDC identity provider. If the URL is HTTP(S)-based, it is the issuer's token endpoint URL to which requests will be made to login based on the configuration in   sasl.jaas.config. If the URL is file-based, it specifies a file containing an access token (in JWT serialized form) issued by the OAuth/OIDC identity provider to use for authorization.
  "sasl.oauthbearer.token.endpoint.url"?: string

  // The fully qualified name of a SASL server callback handler class that implements the AuthenticateCallbackHandler interface. Server callback handlers must be prefixed with listener prefix and SASL   mechanism name in lower-case. For example, listener.name.sasl_ssl.plain.sasl.server.callback.handler.class=com.example.CustomPlainCallbackHandler.
  "sasl.server.callback.handler.class"?: string

  // The maximum receive size allowed before and during initial SASL authentication. Default receive size is 512KB. GSSAPI limits requests to 64K, but we allow upto 512KB by default for custom SASL   mechanisms. In practice, PLAIN, SCRAM and OAUTH mechanisms can use much smaller limits.
  "sasl.server.max.receive.size"?: int | *524288

  // Security protocol used to communicate between brokers. Valid values are: PLAINTEXT, SSL, SASL_PLAINTEXT, SASL_SSL. It is an error to set this and inter.broker.listener.name properties at the same   time.
  "security.inter.broker.protocol"?: string & "PLAINTEXT" | "SSL" | "SASL_PLAINTEXT" | "SASL_SSL" | *"PLAINTEXT"

  // The maximum amount of time the client will wait for the socket connection to be established. The connection setup timeout will increase exponentially for each consecutive connection failure up to   this maximum. To avoid connection storms, a randomization factor of 0.2 will be applied to the timeout resulting in a random range between 20% below and 20% above the computed value.
  "socket.connection.setup.timeout.max.ms"?: int | *30000

  // The amount of time the client will wait for the socket connection to be established. If the connection is not built before the timeout elapses, clients will close the socket channel.
  "socket.connection.setup.timeout.ms"?: int | *10000

  // The maximum number of pending connections on the socket. In Linux, you may also need to configure `somaxconn` and `tcp_max_syn_backlog` kernel parameters accordingly to make the configuration   takes effect.
  "socket.listen.backlog.size"?: int & >=1 | *50

  // A list of cipher suites. This is a named combination of authentication, encryption, MAC and key exchange algorithm used to negotiate the security settings for a network connection using TLS or SSL   network protocol. By default all the available cipher suites are supported.
  "ssl.cipher.suites"?: string | *""

  // Configures kafka broker to request client authentication. The following settings are common:  <ul> <li><code>ssl.client.auth=required</code> If set to required client authentication is required. <  li><code>ssl.client.auth=requested</code> This means client authentication is optional. unlike required, if this option is set client can choose not to provide authentication information about itself   <li><code>ssl.client.auth=none</code> This means client authentication is not needed.</ul>
  "ssl.client.auth"?: string & "required" | "requested" | "none" | *"none"

  // The list of protocols enabled for SSL connections. The default is 'TLSv1.2,TLSv1.3' when running with Java 11 or newer, 'TLSv1.2' otherwise. With the default value for Java 11, clients and servers   will prefer TLSv1.3 if both support it and fallback to TLSv1.2 otherwise (assuming both support at least TLSv1.2). This default should be fine for most cases. Also see the config documentation for   `ssl.protocol`.
  "ssl.enabled.protocols"?: string | *"TLSv1.2"

  // The password of the private key in the key store file or the PEM key specified in `ssl.keystore.key'.
  "ssl.key.password"?: string

  // The algorithm used by key manager factory for SSL connections. Default value is the key manager factory algorithm configured for the Java Virtual Machine.
  "ssl.keymanager.algorithm"?: string | *"SunX509"

  // Certificate chain in the format specified by 'ssl.keystore.type'. Default SSL engine factory supports only PEM format with a list of X.509 certificates
  "ssl.keystore.certificate.chain"?: string

  // Private key in the format specified by 'ssl.keystore.type'. Default SSL engine factory supports only PEM format with PKCS#8 keys. If the key is encrypted, key password must be specified using   'ssl.key.password'
  "ssl.keystore.key"?: string

  // The location of the key store file. This is optional for client and can be used for two-way authentication for client.
  "ssl.keystore.location"?: string

  // The store password for the key store file. This is optional for client and only needed if 'ssl.keystore.location' is configured. Key store password is not supported for PEM format.
  "ssl.keystore.password"?: string

  // The file format of the key store file. This is optional for client. The values currently supported by the default `ssl.engine.factory.class` are [JKS, PKCS12, PEM].
  "ssl.keystore.type"?: string | *"JKS"

  // The SSL protocol used to generate the SSLContext. The default is 'TLSv1.3' when running with Java 11 or newer, 'TLSv1.2' otherwise. This value should be fine for most use cases. Allowed values in   recent JVMs are 'TLSv1.2' and 'TLSv1.3'. 'TLS', 'TLSv1.1', 'SSL', 'SSLv2' and 'SSLv3' may be supported in older JVMs, but their usage is discouraged due to known security vulnerabilities. With the   default value for this config and 'ssl.enabled.protocols', clients will downgrade to 'TLSv1.2' if the server does not support 'TLSv1.3'. If this config is set to 'TLSv1.2', clients will not use   'TLSv1.3' even if it is one of the values in ssl.enabled.protocols and the server only supports 'TLSv1.3'.
  "ssl.protocol"?: string | *"TLSv1.2"

  // The name of the security provider used for SSL connections. Default value is the default security provider of the JVM.
  "ssl.provider"?: string

  // The algorithm used by trust manager factory for SSL connections. Default value is the trust manager factory algorithm configured for the Java Virtual Machine.
  "ssl.trustmanager.algorithm"?: string | *"PKIX"

  // Trusted certificates in the format specified by 'ssl.truststore.type'. Default SSL engine factory supports only PEM format with X.509 certificates.
  "ssl.truststore.certificates"?: string

  // The location of the trust store file.
  "ssl.truststore.location"?: string

  // The password for the trust store file. If a password is not set, trust store file configured will still be used, but integrity checking is disabled. Trust store password is not supported for PEM   format.
  "ssl.truststore.password"?: string

  // The file format of the trust store file. The values currently supported by the default `ssl.engine.factory.class` are [JKS, PKCS12, PEM].
  "ssl.truststore.type"?: string | *"JKS"

  // Typically set to <code>org.apache.zookeeper.ClientCnxnSocketNetty</code> when using TLS connectivity to ZooKeeper. Overrides any explicit value set via the same-named <code>  zookeeper.clientCnxnSocket</code> system property.
  "zookeeper.clientCnxnSocket"?: string

  // Set client to use TLS when connecting to ZooKeeper. An explicit value overrides any value set via the <code>zookeeper.client.secure</code> system property (note the different name). Defaults to   false if neither is set; when true, <code>zookeeper.clientCnxnSocket</code> must be set (typically to <code>org.apache.zookeeper.ClientCnxnSocketNetty</code>); other values to set may include <code>  zookeeper.ssl.cipher.suites</code>, <code>zookeeper.ssl.crl.enable</code>, <code>zookeeper.ssl.enabled.protocols</code>, <code>zookeeper.ssl.endpoint.identification.algorithm</code>, <code>  zookeeper.ssl.keystore.location</code>, <code>zookeeper.ssl.keystore.password</code>, <code>zookeeper.ssl.keystore.type</code>, <code>zookeeper.ssl.ocsp.enable</code>, <code>  zookeeper.ssl.protocol</code>, <code>zookeeper.ssl.truststore.location</code>, <code>zookeeper.ssl.truststore.password</code>, <code>zookeeper.ssl.truststore.type</code>
  "zookeeper.ssl.client.enable"?: bool | *false

  // Keystore location when using a client-side certificate with TLS connectivity to ZooKeeper. Overrides any explicit value set via the <code>zookeeper.ssl.keyStore.location</code> system property (  note the camelCase).
  "zookeeper.ssl.keystore.location"?: string

  // Keystore password when using a client-side certificate with TLS connectivity to ZooKeeper. Overrides any explicit value set via the <code>zookeeper.ssl.keyStore.password</code> system property (  note the camelCase). Note that ZooKeeper does not support a key password different from the keystore password, so be sure to set the key password in the keystore to be identical to the keystore   password; otherwise the connection attempt to Zookeeper will fail.
  "zookeeper.ssl.keystore.password"?: string

  // Keystore type when using a client-side certificate with TLS connectivity to ZooKeeper. Overrides any explicit value set via the <code>zookeeper.ssl.keyStore.type</code> system property (note the   camelCase). The default value of <code>null</code> means the type will be auto-detected based on the filename extension of the keystore.
  "zookeeper.ssl.keystore.type"?: string

  // Truststore location when using TLS connectivity to ZooKeeper. Overrides any explicit value set via the <code>zookeeper.ssl.trustStore.location</code> system property (note the camelCase).
  "zookeeper.ssl.truststore.location"?: string

  // Truststore password when using TLS connectivity to ZooKeeper. Overrides any explicit value set via the <code>zookeeper.ssl.trustStore.password</code> system property (note the camelCase).
  "zookeeper.ssl.truststore.password"?: string

  // Truststore type when using TLS connectivity to ZooKeeper. Overrides any explicit value set via the <code>zookeeper.ssl.trustStore.type</code> system property (note the camelCase). The default   value of <code>null</code> means the type will be auto-detected based on the filename extension of the truststore.
  "zookeeper.ssl.truststore.type"?: string

  // The alter configs policy class that should be used for validation. The class should implement the <code>org.apache.kafka.server.policy.AlterConfigPolicy</code> interface.
  "alter.config.policy.class.name"?: string

  // The number of samples to retain in memory for alter log dirs replication quotas
  "alter.log.dirs.replication.quota.window.num"?: int & >=1 | *11

  // The time span of each sample for alter log dirs replication quotas
  "alter.log.dirs.replication.quota.window.size.seconds"?: int & >=1 | *1

  // The fully qualified name of a class that implements <code>org.apache.kafka.server.authorizer.Authorizer</code> interface, which is used by the broker for authorization.
  "authorizer.class.name"?: string | *""

  // The fully qualified name of a class that implements the ClientQuotaCallback interface, which is used to determine quota limits applied to client requests. By default, the &lt;user&gt; and   &lt;client-id&gt; quotas that are stored in ZooKeeper are applied. For any given request, the most specific quota that matches the user principal of the session and the client-id of the request is   applied.
  "client.quota.callback.class"?: string

  // Connection close delay on failed authentication: this is the time (in milliseconds) by which connection close will be delayed on authentication failure. This must be configured to be less than   connections.max.idle.ms to prevent connection timeout.
  "connection.failed.authentication.delay.ms"?: int & >=0 | *100

  // The amount of time to wait before attempting to retry a failed request to a given topic partition. This avoids repeatedly sending requests in a tight loop under some failure scenarios.
  "controller.quorum.retry.backoff.ms"?: int | *20

  // The number of samples to retain in memory for controller mutation quotas
  "controller.quota.window.num"?: int & >=1 | *11

  // The time span of each sample for controller mutations quotas
  "controller.quota.window.size.seconds"?: int & >=1 | *1

  // The create topic policy class that should be used for validation. The class should implement the <code>org.apache.kafka.server.policy.CreateTopicPolicy</code> interface.
  "create.topic.policy.class.name"?: string

  // Scan interval to remove expired delegation tokens.
  "delegation.token.expiry.check.interval.ms"?: int & >=1 | *3600000

  // The metrics polling interval (in seconds) which can be used in kafka.metrics.reporters implementations.
  "kafka.metrics.polling.interval.secs"?: int & >=1 | *10

  // A list of classes to use as Yammer metrics custom reporters. The reporters should implement <code>kafka.metrics.KafkaMetricsReporter</code> trait. If a client wants to expose JMX operations on a   custom reporter, the custom reporter needs to additionally implement an MBean trait that extends <code>kafka.metrics.KafkaMetricsReporterMBean</code> trait so that the registered MBean is compliant   with the standard MBean convention.
  "kafka.metrics.reporters"?: string | *""

  // Map between listener names and security protocols. This must be defined for the same security protocol to be usable in more than one port or IP. For example, internal and external traffic can be   separated even if SSL is required for both. Concretely, the user could define listeners with names INTERNAL and EXTERNAL and this property as: `INTERNAL:SSL,EXTERNAL:SSL`. As shown, key and value are   separated by a colon and map entries are separated by commas. Each listener name should only appear once in the map. Different security (SSL and SASL) settings can be configured for each listener by   adding a normalised prefix (the listener name is lowercased) to the config name. For example, to set a different keystore for the INTERNAL listener, a config with name <code>  listener.name.internal.ssl.keystore.location</code> would be set. If the config for the listener name is not set, the config will fallback to the generic config (i.e. <code>  ssl.keystore.location</code>). Note that in KRaft a default mapping from the listener names defined by <code>controller.listener.names</code> to PLAINTEXT is assumed if no explicit mapping is   provided and no other security protocol is in use.
  "listener.security.protocol.map"?: string | *"PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT,SASL_SSL:SASL_SSL"

  // This configuration controls whether down-conversion of message formats is enabled to satisfy consume requests. When set to <code>false</code>, broker will not perform down-conversion for consumers   expecting an older message format. The broker responds with <code>UNSUPPORTED_VERSION</code> error for consume requests from such older clients. This configurationdoes not apply to any message format   conversion that might be required for replication to followers.
  "log.message.downconversion.enable"?: bool | *true

  // This configuration controls how often the active controller should write no-op records to the metadata partition. If the value is 0, no-op records are not appended to the metadata partition. The   default value is 500
  "metadata.max.idle.interval.ms"?: int & >=0 | *500

  // A list of classes to use as metrics reporters. Implementing the <code>org.apache.kafka.common.metrics.MetricsReporter</code> interface allows plugging in classes that will be notified of new   metric creation. The JmxReporter is always included to register JMX statistics.
  "metric.reporters"?: string | *""

  // The number of samples maintained to compute metrics.
  "metrics.num.samples"?: int & >=1 | *2

  // The highest recording level for metrics.
  "metrics.recording.level"?: string | *"INFO"

  // The window of time a metrics sample is computed over.
  "metrics.sample.window.ms"?: int & >=1 | *30000

  // The Cipher algorithm used for encoding dynamically configured passwords.
  "password.encoder.cipher.algorithm"?: string | *"AES/CBC/PKCS5Padding"

  // The iteration count used for encoding dynamically configured passwords.
  "password.encoder.iterations"?: int & >=1024 | *4096

  // The key length used for encoding dynamically configured passwords.
  "password.encoder.key.length"?: int & >=8 | *128

  // The SecretKeyFactory algorithm used for encoding dynamically configured passwords. Default is PBKDF2WithHmacSHA512 if available and PBKDF2WithHmacSHA1 otherwise.
  "password.encoder.keyfactory.algorithm"?: string

  // The number of samples to retain in memory for client quotas
  "quota.window.num"?: int & >=1 | *11

  // The time span of each sample for client quotas
  "quota.window.size.seconds"?: int & >=1 | *1

  // The number of samples to retain in memory for replication quotas
  "replication.quota.window.num"?: int & >=1 | *11

  // The time span of each sample for replication quotas
  "replication.quota.window.size.seconds"?: int & >=1 | *1

  // The (optional) value in milliseconds for the external authentication provider connection timeout. Currently applies only to OAUTHBEARER.
  "sasl.login.connect.timeout.ms"?: int

  // The (optional) value in milliseconds for the external authentication provider read timeout. Currently applies only to OAUTHBEARER.
  "sasl.login.read.timeout.ms"?: int

  // The (optional) value in milliseconds for the maximum wait between login attempts to the external authentication provider. Login uses an exponential backoff algorithm with an initial wait based on   the sasl.login.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.login.retry.backoff.max.ms setting. Currently applies only to   OAUTHBEARER.
  "sasl.login.retry.backoff.max.ms"?: int | *10000

  // The (optional) value in milliseconds for the initial wait between login attempts to the external authentication provider. Login uses an exponential backoff algorithm with an initial wait based on   the sasl.login.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the sasl.login.retry.backoff.max.ms setting. Currently applies only to   OAUTHBEARER.
  "sasl.login.retry.backoff.ms"?: int | *100

  // The (optional) value in seconds to allow for differences between the time of the OAuth/OIDC identity provider and the broker.
  "sasl.oauthbearer.clock.skew.seconds"?: int | *30

  // The (optional) comma-delimited setting for the broker to use to verify that the JWT was issued for one of the expected audiences. The JWT will be inspected for the standard OAuth "aud" claim and   if this value is set, the broker will match the value from JWT's "aud" claim  to see if there is an exact match. If there is no match, the broker will reject the JWT and authentication will fail.
  "sasl.oauthbearer.expected.audience"?: string

  // The (optional) setting for the broker to use to verify that the JWT was created by the expected issuer. The JWT will be inspected for the standard OAuth "iss" claim and if this value is set, the   broker will match it exactly against what is in the JWT's "iss" claim. If there is no match, the broker will reject the JWT and authentication will fail.
  "sasl.oauthbearer.expected.issuer"?: string

  // The (optional) value in milliseconds for the broker to wait between refreshing its JWKS (JSON Web Key Set) cache that contains the keys to verify the signature of the JWT.
  "sasl.oauthbearer.jwks.endpoint.refresh.ms"?: int | *3600000

  // The (optional) value in milliseconds for the maximum wait between attempts to retrieve the JWKS (JSON Web Key Set) from the external authentication provider. JWKS retrieval uses an exponential   backoff algorithm with an initial wait based on the sasl.oauthbearer.jwks.endpoint.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by   the sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms setting.
  "sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms"?: int | *10000

  // The (optional) value in milliseconds for the initial wait between JWKS (JSON Web Key Set) retrieval attempts from the external authentication provider. JWKS retrieval uses an exponential backoff   algorithm with an initial wait based on the sasl.oauthbearer.jwks.endpoint.retry.backoff.ms setting and will double in wait length between attempts up to a maximum wait length specified by the   sasl.oauthbearer.jwks.endpoint.retry.backoff.max.ms setting.
  "sasl.oauthbearer.jwks.endpoint.retry.backoff.ms"?: int | *100

  // The OAuth claim for the scope is often named "scope", but this (optional) setting can provide a different name to use for the scope included in the JWT payload's claims if the OAuth/OIDC provider   uses a different name for that claim.
  "sasl.oauthbearer.scope.claim.name"?: string | *"scope"

  // The OAuth claim for the subject is often named "sub", but this (optional) setting can provide a different name to use for the subject included in the JWT payload's claims if the OAuth/OIDC   provider uses a different name for that claim.
  "sasl.oauthbearer.sub.claim.name"?: string | *"sub"

  // A list of configurable creator classes each returning a provider implementing security algorithms. These classes should implement the <code>  org.apache.kafka.common.security.auth.SecurityProviderCreator</code> interface.
  "security.providers"?: string

  // The endpoint identification algorithm to validate server hostname using server certificate.
  "ssl.endpoint.identification.algorithm"?: string | *"https"

  // The class of type org.apache.kafka.common.security.auth.SslEngineFactory to provide SSLEngine objects. Default value is org.apache.kafka.common.security.ssl.DefaultSslEngineFactory
  "ssl.engine.factory.class"?: string

  // A list of rules for mapping from distinguished name from the client certificate to short name. The rules are evaluated in order and the first rule that matches a principal name is used to map it   to a short name. Any later rules in the list are ignored. By default, distinguished name of the X.500 certificate will be the principal. For more details on the format please see <a   href="#security_authz"> security authorization and acls</a>. Note that this configuration is ignored if an extension of KafkaPrincipalBuilder is provided by the <code>principal.builder.class</code>   configuration.
  "ssl.principal.mapping.rules"?: string | *"DEFAULT"

  // The SecureRandom PRNG implementation to use for SSL cryptography operations.
  "ssl.secure.random.implementation"?: string

  // The interval at which to rollback transactions that have timed out
  "transaction.abort.timed.out.transaction.cleanup.interval.ms"?: int & >=1 | *10000

  // The interval at which to remove transactions that have expired due to <code>transactional.id.expiration.ms</code> passing
  "transaction.remove.expired.transaction.cleanup.interval.ms"?: int & >=1 | *3600000

  // Specifies the enabled cipher suites to be used in ZooKeeper TLS negotiation (csv). Overrides any explicit value set via the <code>zookeeper.ssl.ciphersuites</code> system property (note the single   word "ciphersuites"). The default value of <code>null</code> means the list of enabled cipher suites is determined by the Java runtime being used.
  "zookeeper.ssl.cipher.suites"?: string

  // Specifies whether to enable Certificate Revocation List in the ZooKeeper TLS protocols. Overrides any explicit value set via the <code>zookeeper.ssl.crl</code> system property (note the shorter   name).
  "zookeeper.ssl.crl.enable"?: bool | *false

  // Specifies the enabled protocol(s) in ZooKeeper TLS negotiation (csv). Overrides any explicit value set via the <code>zookeeper.ssl.enabledProtocols</code> system property (note the camelCase). The   default value of <code>null</code> means the enabled protocol will be the value of the <code>zookeeper.ssl.protocol</code> configuration property.
  "zookeeper.ssl.enabled.protocols"?: string

  // Specifies whether to enable hostname verification in the ZooKeeper TLS negotiation process, with (case-insensitively) "https" meaning ZooKeeper hostname verification is enabled and an explicit   blank value meaning it is disabled (disabling it is only recommended for testing purposes). An explicit value overrides any "true" or "false" value set via the <code>  zookeeper.ssl.hostnameVerification</code> system property (note the different name and values; true implies https and false implies blank).
  "zookeeper.ssl.endpoint.identification.algorithm"?: string | *"HTTPS"

  // Specifies whether to enable Online Certificate Status Protocol in the ZooKeeper TLS protocols. Overrides any explicit value set via the <code>zookeeper.ssl.ocsp</code> system property (note the   shorter name).
  "zookeeper.ssl.ocsp.enable"?: bool | *false

  // Specifies the protocol to be used in ZooKeeper TLS negotiation. An explicit value overrides any value set via the same-named <code>zookeeper.ssl.protocol</code> system property.
  "zookeeper.ssl.protocol"?: string | *"TLSv1.2"

	// other parameters
	...
}

configuration: #KafkaParameter & {
}
