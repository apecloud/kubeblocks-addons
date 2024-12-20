#KafkaParameter: {
    "advertised.host.name"?: string | *""
    "advertised.listeners"?: string | *""
    "advertised.port"?: int | *9092
    "alter.config.policy.class.name"?: string | *""
    "alter.log.dirs.replication.quota.window.num"?: int | *11
    "alter.log.dirs.replication.quota.window.size.seconds"?: int | *1
    "authorizer.class.name"?: string | *""
    "auto.create.topics.enable"?: bool | *true
    "auto.leader.rebalance.enable"?: bool | *true
    "background.threads"?: int | *10
    "broker.id.generation.enable"?: bool | *true
    "broker.id"?: int | *-1
    "broker.rack"?: string | *""
    "client.quota.callback.class"?: string | *""
    "compression.type"?: string | *"producer"
    "connection.failed.authentication.delay.ms"?: int | *100
    "connections.max.idle.ms"?: int | *600000
    "connections.max.reauth.ms"?: int | *0
    "control.plane.listener.name"?: string | *""
    "controlled.shutdown.enable"?: bool | *true
    "controlled.shutdown.max.retries"?: int | *3
    "controlled.shutdown.retry.backoff.ms"?: int | *5000
    "controller.quota.window.num"?: int | *11
    "controller.quota.window.size.seconds"?: int | *1
    "controller.socket.timeout.ms"?: int | *30000
    "create.topic.policy.class.name"?: string | *""
    "default.replication.factor"?: int | *1
    "delegation.token.expiry.check.interval.ms"?: int | *3600000
    "delegation.token.expiry.time.ms"?: int | *86400000
    "delegation.token.master.key"?: string | *""
    "delegation.token.max.lifetime.ms"?: int | *604800000
    "delete.records.purgatory.purge.interval.requests"?: int | *1
    "delete.topic.enable"?: bool | *true
    "fetch.max.bytes"?: int | *57671680
    "fetch.purgatory.purge.interval.requests"?: int | *1000
    "group.initial.rebalance.delay.ms"?: int | *3000
    "group.max.session.timeout.ms"?: int | *1800000
    "group.max.size"?: int | *2147483647
    "group.min.session.timeout.ms"?: int | *6000
    "host.name"?: string | *""
    "inter.broker.listener.name"?: string | *""
    "inter.broker.protocol.version"?: string | *"2.7-IV2"
    "kafka.metrics.polling.interval.secs"?: int | *10
    "kafka.metrics.reporters"?: string | *""
    "leader.imbalance.check.interval.seconds"?: int | *300
    "leader.imbalance.per.broker.percentage"?: int | *10
    "listener.security.protocol.map"?: string | *"PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT,SASL_SSL:SASL_SSL"
    "listeners"?: string | *""
    "log.cleaner.backoff.ms"?: int | *15000
    "log.cleaner.dedupe.buffer.size"?: int | *134217728
    "log.cleaner.delete.retention.ms"?: int | *86400000
    "log.cleaner.enable"?: bool | *true
    "log.cleaner.io.buffer.load.factor"?: float | *0.9
    "log.cleaner.io.buffer.size"?: int | *524288
    "log.cleaner.io.max.bytes.per.second"?: float | *1.7976931348623157e308
    "log.cleaner.max.compaction.lag.ms"?: int | *9223372036854775807
    "log.cleaner.min.cleanable.ratio"?: float | *0.5
    "log.cleaner.min.compaction.lag.ms"?: int | *0
    "log.cleaner.threads"?: int | *1
    "log.cleanup.policy"?: string | *"delete"
    "log.dir"?: string | *"/tmp/kafka-logs"
    "log.dirs"?: string | *""
    "log.flush.interval.messages"?: int | *9223372036854775807
    "log.flush.interval.ms"?: int | *0
    "log.flush.offset.checkpoint.interval.ms"?: int | *60000
    "log.flush.scheduler.interval.ms"?: int | *9223372036854775807
    "log.flush.start.offset.checkpoint.interval.ms"?: int | *60000
    "log.index.interval.bytes"?: int | *4096
    "log.index.size.max.bytes"?: int | *10485760
    "log.message.downconversion.enable"?: bool | *true
    "log.message.format.version"?: string | *"2.7-IV2"
    "log.message.timestamp.difference.max.ms"?: int | *9223372036854775807
    "log.message.timestamp.type"?: string | *"CreateTime"
    "log.preallocate"?: bool | *false
    "log.retention.bytes"?: int | *-1
    "log.retention.check.interval.ms"?: int | *300000
    "log.retention.hours"?: int | *168
    "log.retention.minutes"?: int | *0
    "log.retention.ms"?: int | *0
    "log.roll.hours"?: int | *168
    "log.roll.jitter.hours"?: int | *0
    "log.roll.jitter.ms"?: int | *0
    "log.roll.ms"?: int | *0
    "log.segment.bytes"?: int | *1073741824
    "log.segment.delete.delay.ms"?: int | *60000
    "max.connection.creation.rate"?: int | *2147483647
    "max.connections.per.ip.overrides"?: string | *""
    "max.connections.per.ip"?: int | *2147483647
    "max.connections"?: int | *2147483647
    "max.incremental.fetch.session.cache.slots"?: int | *1000
    "message.max.bytes"?: int | *1048588
    "metric.reporters"?: string | *""
    "metrics.num.samples"?: int | *2
    "metrics.recording.level"?: string | *"INFO"
    "metrics.sample.window.ms"?: int | *30000
    "min.insync.replicas"?: int | *1
    "num.io.threads"?: int | *8
    "num.network.threads"?: int | *3
    "num.partitions"?: int | *1
    "num.recovery.threads.per.data.dir"?: int | *1
    "num.replica.alter.log.dirs.threads"?: int | *0
    "num.replica.fetchers"?: int | *1
    "offset.metadata.max.bytes"?: int | *4096
    "offsets.commit.required.acks"?: int | *-1
    "offsets.commit.timeout.ms"?: int | *5000
    "offsets.load.buffer.size"?: int | *5242880
    "offsets.retention.check.interval.ms"?: int | *600000
    "offsets.retention.minutes"?: int | *10080
    "offsets.topic.compression.codec"?: int | *0
    "offsets.topic.num.partitions"?: int | *50
    "offsets.topic.replication.factor"?: int | *3
    "offsets.topic.segment.bytes"?: int | *104857600
    "password.encoder.cipher.algorithm"?: string | *"AES/CBC/PKCS5Padding"
    "password.encoder.iterations"?: int | *4096
    "password.encoder.key.length"?: int | *128
    "password.encoder.keyfactory.algorithm"?: string | *""
    "password.encoder.old.secret"?: string | *""
    "password.encoder.secret"?: string | *""
    "port"?: int | *9092
    "principal.builder.class"?: string | *""
    "producer.purgatory.purge.interval.requests"?: int | *1000
    "queued.max.request.bytes"?: int | *-1
    "queued.max.requests"?: int | *500
    "quota.consumer.default"?: int | *9223372036854775807
    "quota.producer.default"?: int | *9223372036854775807
    "quota.window.num"?: int | *11
    "quota.window.size.seconds"?: int | *1
    "replica.fetch.backoff.ms"?: int | *1000
    "replica.fetch.max.bytes"?: int | *1048576
    "replica.fetch.min.bytes"?: int | *1
    "replica.fetch.response.max.bytes"?: int | *10485760
    "replica.fetch.wait.max.ms"?: int | *500
    "replica.high.watermark.checkpoint.interval.ms"?: int | *5000
    "replica.lag.time.max.ms"?: int | *30000
    "replica.selector.class"?: string | *""
    "replica.socket.receive.buffer.bytes"?: int | *65536
    "replica.socket.timeout.ms"?: int | *30000
    "replication.quota.window.num"?: int | *11
    "replication.quota.window.size.seconds"?: int | *1
    "request.timeout.ms"?: int | *30000
    "reserved.broker.max.id"?: int | *1000
    "sasl.client.callback.handler.class"?: string | *""
    "sasl.enabled.mechanisms"?: string | *"GSSAPI"
    "sasl.jaas.config"?: string | *""
    "sasl.kerberos.kinit.cmd"?: string | *"/usr/bin/kinit"
    "sasl.kerberos.min.time.before.relogin"?: int | *60000
    "sasl.kerberos.principal.to.local.rules"?: string | *"DEFAULT"
    "sasl.kerberos.service.name"?: string | *""
    "sasl.kerberos.ticket.renew.jitter"?: float | *0.05
    "sasl.kerberos.ticket.renew.window.factor"?: float | *0.8
    "sasl.login.callback.handler.class"?: string | *""
    "sasl.login.class"?: string | *""
    "sasl.login.refresh.buffer.seconds"?: int | *300
    "sasl.login.refresh.min.period.seconds"?: int | *60
    "sasl.login.refresh.window.factor"?: float | *0.8
    "sasl.login.refresh.window.jitter"?: float | *0.05
    "sasl.mechanism.inter.broker.protocol"?: string | *"GSSAPI"
    "sasl.server.callback.handler.class"?: string | *""
    "security.inter.broker.protocol"?: string | *"PLAINTEXT"
    "security.providers"?: string | *""
    "socket.connection.setup.timeout.max.ms"?: int | *127000
    "socket.connection.setup.timeout.ms"?: int | *10000
    "socket.receive.buffer.bytes"?: int | *102400
    "socket.request.max.bytes"?: int | *104857600
    "socket.send.buffer.bytes"?: int | *102400
    "ssl.cipher.suites"?: string | *""
    "ssl.client.auth"?: string | *"none"
    "ssl.enabled.protocols"?: string | *"TLSv1.2"
    "ssl.endpoint.identification.algorithm"?: string | *"https"
    "ssl.engine.factory.class"?: string | *""
    "ssl.key.password"?: string | *""
    "ssl.keymanager.algorithm"?: string | *"SunX509"
    "ssl.keystore.certificate.chain"?: string | *""
    "ssl.keystore.key"?: string | *""
    "ssl.keystore.location"?: string | *""
    "ssl.keystore.password"?: string | *""
    "ssl.keystore.type"?: string | *"JKS"
    "ssl.principal.mapping.rules"?: string | *"DEFAULT"
    "ssl.protocol"?: string | *"TLSv1.2"
    "ssl.provider"?: string | *""
    "ssl.secure.random.implementation"?: string | *""
    "ssl.trustmanager.algorithm"?: string | *"PKIX"
    "ssl.truststore.certificates"?: string | *""
    "ssl.truststore.location"?: string | *""
    "ssl.truststore.password"?: string | *""
    "ssl.truststore.type"?: string | *"JKS"
    "transaction.abort.timed.out.transaction.cleanup.interval.ms"?: int | *10000
    "transaction.max.timeout.ms"?: int | *900000
    "transaction.remove.expired.transaction.cleanup.interval.ms"?: int | *3600000
    "transaction.state.log.load.buffer.size"?: int | *5242880
    "transaction.state.log.min.isr"?: int | *2
    "transaction.state.log.num.partitions"?: int | *50
    "transaction.state.log.replication.factor"?: int | *3
    "transaction.state.log.segment.bytes"?: int | *104857600
    "transactional.id.expiration.ms"?: int | *604800000
    "unclean.leader.election.enable"?: bool | *false
    "zookeeper.clientCnxnSocket"?: string | *""
    "zookeeper.connect"?: string | *""
    "zookeeper.connection.timeout.ms"?: int | *0
    "zookeeper.max.in.flight.requests"?: int | *10
    "zookeeper.session.timeout.ms"?: int | *18000
    "zookeeper.set.acl"?: bool | *false
    "zookeeper.ssl.cipher.suites"?: string | *""
    "zookeeper.ssl.client.enable"?: bool | *false
    "zookeeper.ssl.crl.enable"?: bool | *false
    "zookeeper.ssl.enabled.protocols"?: string | *""
    "zookeeper.ssl.endpoint.identification.algorithm"?: string | *"HTTPS"
    "zookeeper.ssl.keystore.location"?: string | *""
    "zookeeper.ssl.keystore.password"?: string | *""
    "zookeeper.ssl.keystore.type"?: string | *""
    "zookeeper.ssl.ocsp.enable"?: bool | *false
    "zookeeper.ssl.protocol"?: string | *"TLSv1.2"
    "zookeeper.ssl.truststore.location"?: string | *""
    "zookeeper.ssl.truststore.password"?: string | *""
    "zookeeper.ssl.truststore.type"?: string | *""
    "zookeeper.sync.time.ms"?: int | *2000
    ...
}

configuration: #KafkaParameter & {
}