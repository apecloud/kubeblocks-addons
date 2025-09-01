#MongodSetParamParameter: {
	// (Authentication) Allows or disallows the retrieval of authorization roles from client X.509 certificates.
	allowRolesFromX509Certificates: bool & *true | false

	// (Authentication) A comma-separated list of authentication mechanisms the server accepts.
	authenticationMechanisms: string

	// (Authentication) The number of milliseconds to wait before informing clients that their authentication attempt has failed.
	authFailedDelayMs: int & *0

	// (Authentication) Maximum number of retries for AWS IAM authentication after a connection failure.
	awsSTSRetryCount: int & *2

	// (Authentication) The mode for cluster member authentication, used for rolling upgrades to x509.
	clusterAuthMode: string | "sendX509" | "x509"

	// (Authentication) Enables or disables the localhost authentication bypass.
	enableLocalhostAuthBypass: bool & *true | false

	// (Authentication) Disables the O/OU/DC check when clusterAuthMode is keyFile.
	enforceUserClusterSeparation: bool & *true | false

	// (Authentication) The number of seconds for which an HMAC signing key is valid before rotating to the next one.
	KeysRotationIntervalSec: int & *7776000

	// (Authentication) The interval in milliseconds between health checks of pooled LDAP connections.
	ldapConnectionPoolHostRefreshIntervalMillis: int & *60000

	// (Authentication) The maximum number of seconds that pooled connections to an LDAP server can remain idle before being closed.
	ldapConnectionPoolIdleHostTimeoutSecs: int & *300

	// (Authentication) The maximum number of in-progress connect operations to each LDAP server.
	ldapConnectionPoolMaximumConnectionsInProgressPerHost: int & *2

	// (Authentication) The maximum number of connections to keep open to each LDAP server.
	ldapConnectionPoolMaximumConnectionsPerHost: int & *2147483647

	// (Authentication) The minimum number of connections to keep open to each LDAP server.
	ldapConnectionPoolMinimumConnectionsPerHost: int | *1

	// (Authentication) Determines if the LDAP connection pool should use latency to determine host priority.
	ldapConnectionPoolUseLatencyForHostPriority: bool & *true | false

	// (Authentication) Enables concurrent LDAP operations. Only use if libldap is thread-safe.
	ldapForceMultiThreadMode: bool & *false

	// (Authentication) The password used to bind to an LDAP server.
	ldapQueryPassword: string

	// (Authentication) The user that binds to an LDAP server.
	ldapQueryUser: string

	// (Authentication) Number of operation retries by the server LDAP manager after a network error.
	ldapRetryCount: int & *0

	// (Authentication) Determines whether cached user entries from LDAP should be refreshed or just invalidated.
	ldapShouldRefreshUserCacheEntries: bool & *true | false

	// (Authentication) The interval in seconds at which the mongod instance waits between external user cache flushes.
	ldapUserCacheInvalidationInterval: int & *30

	// (Authentication) The interval in seconds that mongod waits before refreshing cached user information from the LDAP server.
	ldapUserCacheRefreshInterval: int & *30

	// (Authentication) The maximum memory usage limit in megabytes for the validate command.
	maxValidateMemoryUsageMB: int & *200

	// (Authentication) Enables or disables OCSP on Linux and macOS.
	ocspEnabled: bool & *true | false

	// (Authentication) Specifies one or more identity provider (IDP) configurations for use with OIDC.
	oidcIdentityProviders: [...{...}]

	// (Authentication) Specifies the cipher string for OpenSSL when using TLS 1.2 or earlier.
	opensslCipherConfig: string

	// (Authentication) Specifies the list of supported cipher suites OpenSSL should permit when using TLS 1.3 encryption.
	opensslCipherSuiteConfig: string

	// (Authentication) Specifies the path to the PEM file that contains the OpenSSL Diffie-Hellman parameters.
	opensslDiffieHellmanParameters: string

	// (Authentication) Instructs the server to check the connectivity of accepted connections before processing them.
	pessimisticConnectivityCheckForAcceptedConnections: bool & *false

	// (Authentication) Specifies the path to the Unix Domain Socket of the saslauthd instance for proxy authentication.
	saslauthdPath: string

	// (Authentication) Overrides MongoDB's default hostname detection for configuring SASL and Kerberos.
	saslHostName: string

	// (Authentication) Overrides the default Kerberos service name component of the Kerberos principal name.
	saslServiceName: string | *"mongodb"

	// (Authentication) Changes the number of hashing iterations used for all new SCRAM-SHA-1 passwords.
	scramIterationCount: int & >=5000 | *10000

	// (Authentication) Changes the number of hashing iterations used for all new SCRAM-SHA-256 passwords.
	scramSHA256IterationCount: int & >=5000 | *15000

	// (Authentication) Sets the TLS mode, useful during a rolling upgrade to TLS/SSL to minimize downtime.
	tlsMode: string | "preferTLS" | "requireTLS"

	// (Authentication) Overrides the net.tls.clusterAuthX509 configuration options.
	tlsClusterAuthX509Override: string

	// (Authentication) Controls the warning threshold in days for X.509 certificate expiration.
	tlsX509ExpirationWarningThresholdDays: int & >=0 | *30

	// (Authentication) Directs the instance to withhold sending its TLS certificate during intra-cluster communications.
	tlsWithholdClientCertificate: bool & *false

	// (General) By default, allows pipeline stages that require more than 100MB of memory to write temporary files to disk.
	allowDiskUseByDefault: bool & *true

	// (General) Sets the maximum size of the legacy connection pools for outgoing connections to other mongod instances.
	connPoolMaxConnsPerHost: int | *200

	// (General) Sets the maximum number of in-use connections for the legacy global connection pool.
	connPoolMaxInUseConnsPerHost: int

	// (General) Sets the expiration threshold in milliseconds for idle cursors.
	cursorTimeoutMillis: int | *600000

	// (General) Allows a server receiving a step up/down request to terminate if it cannot comply within the timeout.
	fassertOnLockTimeoutForStepUpDown: int | *15

	// (General) Sets the time limit that connections in the legacy global connection pool can remain idle.
	globalConnPoolIdleTimeoutMinutes: int

	// (General) Adds more verbose tracing for curl on Linux and macOS.
	httpVerboseLogging: bool | *false

	// (General) Sets the minimum available disk space in megabytes required for index builds.
	indexBuildMinAvailableDiskSpaceMB: int & >=0 & <=8000000 | *500

	// (General) Limits the maximum number of keys generated for a single document to prevent out-of-memory errors.
	indexMaxNumGeneratedKeysPerDocument: int | *100000

	// (General) Controls the maximum number of operations admitted concurrently to the ingress queue.
	ingressAdmissionControllerTicketPoolSize: int | *1000000

	// (General) Determines whether rate limiting for new connection establishment is enabled.
	ingressConnectionEstablishmentRateLimiterEnabled: bool | *false

	// (General) Specifies the maximum number of new connections that can be established per second when rate limiting is enabled.
	ingressConnectionEstablishmentRatePerSec: int & >=1

	// (General) Describes how many seconds worth of connection establishments the server can admit before rate limiting begins.
	ingressConnectionEstablishmentBurstCapacitySecs: float & >=1

	// (General) Specifies the maximum number of connection attempts in the connection establishment queue.
	ingressConnectionEstablishmentMaxQueueDepth: int & >=0 | *0

	// (General) Provides a list of IP addresses and CIDR ranges that the server must exempt from connection establishment rate limits.
	ingressConnectionEstablishmentRateLimiterBypass: [...string]

	// (General) Limits the amount of memory that simultaneous index builds on one collection may consume.
	maxIndexBuildMemoryUsageMegabytes: int | *200

	// (General) Sets the maximum number of concurrent index builds allowed on the primary.
	maxNumActiveUserIndexBuilds: int | *3

	// (General) Prevents running queries that require a collection scan.
	notablescan: bool | *false

	// (General) Determines if the serverStatus command returns opWriteConcernCounters information.
	reportOpWriteConcernCountersInServerStatus: bool & *false

	// (General) Sets the time limit in milliseconds to log the establishment of slow server connections.
	slowConnectionThresholdMillis: int | *100

	// (General) Enables a background thread that periodically releases memory back to the operating system.
	tcmallocEnableBackgroundThread: bool | *true

	// (General) Specifies the minimum rate at which TCMalloc releases unused memory to the system (bytes per second).
	tcmallocReleaseRate: float | *0.0

	// (General) Maximum number of retry attempts when an upsert operation encounters a duplicate key error.
	upsertMaxRetryAttemptsOnDuplicateKeyError: int | *100

	// (Replication and Consistency) Specifies whether the replica set allows the use of multiple arbiters.
	allowMultipleArbiters: bool | *false

	// (Replication and Consistency) Sets the connection timeout, in milliseconds, for the replica set monitor.
	connectTimeoutMs: int & >=500 | *10000

	// (Replication and Consistency) Determines if MongoDB creates rollback files containing documents affected during a rollback.
	createRollbackDataFiles: bool & *true

	// (Replication and Consistency) Enables or disables the flow control mechanism to keep secondaries from lagging.
	enableFlowControl: bool | *true

	// (Replication and Consistency) Allows secondary members to replicate from other secondaries even if settings.chainingAllowed is false.
	enableOverrideClusterChainingSetting: bool | *false

	// (Replication and Consistency) The target maximum 'majority committed' lag in seconds when running with flow control.
	flowControlTargetLagSeconds: int & >0 | *10

	// (Replication and Consistency) The amount of time to wait to log a warning once the flow control mechanism detects the majority commit point has not moved.
	flowControlWarnThresholdSeconds: int & >=0 | *10

	// (Replication and Consistency) How long, in milliseconds, to wait between hello requests or RTT measurements.
	heartBeatFrequencyMs: int & >=500 | *10000

	// (Replication and Consistency) Method used for initial sync ('logical' or 'fileCopyBased').
	initialSyncMethod: string | *"logical" | "fileCopyBased"

	// (Replication and Consistency) The preferred source for performing initial sync.
	initialSyncSourceReadPreference: string | "primary" | "primaryPreferred" | "secondary" | "secondaryPreferred" | "nearest"

	// (Replication and Consistency) The time in seconds a secondary performing initial sync attempts to resume if interrupted by a transient network error.
	initialSyncTransientErrorRetryPeriodSeconds: int | *86400

	// (Replication and Consistency) The time in minutes that a session remains active after its most recent use. For testing only.
	localLogicalSessionTimeoutMinutes: int | *30

	// (Replication and Consistency) Defines the length of the latency window in milliseconds used in server selection.
	localThresholdMs: int & >=0 | *15

	// (Replication and Consistency) The interval (in milliseconds) at which the cache refreshes its logical session records.
	logicalSessionRefreshMillis: int | *300000

	// (Replication and Consistency) The maximum amount by which the current cluster time can be advanced.
	maxAcceptableLogicalClockDriftSecs: int | *31536000

	// (Replication and Consistency) The maximum number of sync source changes per hour before a node temporarily stops re-evaluating.
	maxNumSyncSourceChangesPerHour: int | *3

	// (Replication and Consistency) The maximum number of sessions that can be cached.
	maxSessions: int | *1000000

	// (Replication and Consistency) Specifies the settings for mirrored reads for the mongod instance.
	mirrorReads: {
		samplingRate: float | *0.01
		maxTimeMS:    int | *1000
	}

	// (Replication and Consistency) The number of milliseconds to delay applying batches of oplog operations on secondary nodes.
	oplogBatchDelayMillis: int | *0

	// (Replication and Consistency) Enables or disables streaming replication.
	oplogFetcherUsesExhaust: bool | *true

	// (Replication and Consistency) Maximum time in seconds for a replica set member to wait for the find command to finish during data synchronization.
	oplogInitialFindMaxSeconds: int | *60

	// (Replication and Consistency) The duration in seconds between noop writes on each individual node.
	periodicNoopIntervalSecs: int | *10

	// (Replication and Consistency) Sets the maximum oplog application batch size in bytes.
	replBatchLimitBytes: int & >=16777216 & <=104857600 | *104857600

	// (Replication and Consistency) Determines which replica set monitor protocol to use ('streamable' or 'sdam').
	replicaSetMonitorProtocol: string | *"streamable" | "sdam"

	// (Replication and Consistency) Minimum number of threads to use to apply replicated operations in parallel.
	replWriterMinThreadCount: int & >=0 & <=256 | *0

	// (Replication and Consistency) Maximum number of threads to use to apply replicated operations in parallel.
	replWriterThreadCount: int & >=1 & <=256 | *16

	// (Replication and Consistency) Maximum age of data that can be rolled back.
	rollbackTimeLimitSecs: int & >=0 | *86400

	// (Replication and Consistency) The minimum lifetime a transaction record exists in the transactions collection before cleanup.
	TransactionRecordMinimumLifetimeMinutes: int | *30

	// (Replication and Consistency) The length of time a secondary must wait before making a no-op write to advance the last applied time.
	waitForSecondaryBeforeNoopWriteMS: int | *10

	// (Sharding) The default number of documents to sample when running analyzeShardKey.
	analyzeShardKeyCharacteristicsDefaultSampleSize: int & >0 | *10000000

	// (Sharding) The correlation coefficient threshold to determine if a shard key is monotonically changing.
	analyzeShardKeyMonotonicityCorrelationCoefficientThreshold: float & >0 & <=1.0 | *0.7

	// (Sharding) The number of most common shard key values to return.
	analyzeShardKeyNumMostCommonValues: int & >0 & <=1000 | *5

	// (Sharding) The number of ranges to partition the shard key space into when calculating hotness.
	analyzeShardKeyNumRanges: int & >0 & <=10000 | *100

	// (Sharding) The interval in seconds between automerging rounds.
	autoMergerIntervalSecs: int | *3600

	// (Sharding) The minimum time in milliseconds between merges initiated by the AutoMerger on the same collection.
	autoMergerThrottlingMS: int | *15000

	// (Sharding) Specifies the minimum amount of time between two consecutive balancing rounds.
	balancerMigrationsThrottlingMs: int | *1000

	// (Sharding) Maximum number of entries allowed in the catalog cache for collections.
	catalogCacheCollectionMaxEntries: int | *10000

	// (Sharding) Maximum number of entries allowed in the catalog cache for databases.
	catalogCacheDatabaseMaxEntries: int | *10000

	// (Sharding) Maximum number of entries allowed in the catalog cache for indexes.
	catalogCacheIndexMaxEntries: int | *10000

	// (Sharding) The minimum time period (in milliseconds) between consecutive split and merge commands run by the balancer.
	chunkDefragmentationThrottlingMS: int | *0

	// (Sharding) If true, pauses the cleanup of orphaned documents on the shard.
	disableResumableRangeDeleter: bool & *false

	// (Sharding) If set on the config server's primary, enables or disables the index consistency check for sharded collections.
	enableShardedIndexConsistencyCheck: bool | *true

	// (Sharding) The timeout in milliseconds for find operations on the config.chunks collection.
	findChunksOnConfigTimeoutMS: int | *900000

	// (Sharding) Maximum percentage of untransferred data allowed for a migration to transition from catchup to commit phase.
	maxCatchUpPercentageBeforeBlockingWrites: int | *10

	// (Sharding) Limits the time a shard waits for a critical section within a transaction.
	metadataRefreshInTransactionMaxWaitBehindCritSecMS: int | *500

	// (Sharding) Time in milliseconds to wait between batches of insertions during the cloning step of migration.
	migrateCloneInsertionBatchDelayMS: int | *0

	// (Sharding) The maximum number of documents to insert in a single batch during the cloning step of migration.
	migrateCloneInsertionBatchSize: int | *0

	// (Sharding) Minimum delay before a migrated chunk is deleted from the source shard.
	orphanCleanupDelaySecs: int | *900

	// (Sharding) Specifies the maximum batch size used for updating the persisted chunk cache.
	persistedChunkCacheUpdateMaxBatchSize: int | *1000

	// (Sharding) Interval that a sampler (mongos or mongod) refreshes its query analyzer sample rates.
	queryAnalysisSamplerConfigurationRefreshSecs: int | *10

	// (Sharding) Interval that sampled queries are written to disk, in seconds.
	queryAnalysisWriterIntervalSecs: int | *90

	// (Sharding) Maximum number of sampled queries to write to disk at once.
	queryAnalysisWriterMaxBatchSize: int & >0 & <=100000 | *100000

	// (Sharding) Maximum amount of memory in bytes that the query sampling writer is allowed to use.
	queryAnalysisWriterMaxMemoryUsageBytes: int & >0 | *104857600

	// (Sharding) The amount of time in milliseconds to wait before the next batch of deletion during range migration cleanup.
	rangeDeleterBatchDelayMS: int | *20

	// (Sharding) The maximum number of documents in each batch to delete during range migration cleanup.
	rangeDeleterBatchSize: int | *2147483647

	// (Sharding) Specifies the size of the routing table cache buckets used to implement chunk grouping optimization.
	routingTableCacheChunkBucketSize: int & >0 | *500

	// (Sharding) The interval, in milliseconds, at which the config server's primary checks the index consistency of sharded collections.
	shardedIndexConsistencyCheckIntervalMS: int | *600000

	// (Sharding) Maximum time mongos goes without communication to a host before it drops all connections to the host.
	ShardingTaskExecutorPoolHostTimeoutMS: int | *300000

	// (Sharding) Maximum number of simultaneous initiating connections each TaskExecutor connection pool can have to a mongod instance.
	ShardingTaskExecutorPoolMaxConnecting: int | *2

	// (Sharding) Maximum number of outbound connections each TaskExecutor connection pool can open to any given mongod instance.
	ShardingTaskExecutorPoolMaxSize: int

	// (Sharding) Optional override for ShardingTaskExecutorPoolMaxSize for connections to a configuration server.
	ShardingTaskExecutorPoolMaxSizeForConfigServers: int | *-1

	// (Sharding) Minimum number of outbound connections each TaskExecutor connection pool can open to any given mongod instance.
	ShardingTaskExecutorPoolMinSize: int | *1

	// (Sharding) Optional override for ShardingTaskExecutorPoolMinSize for connections to a configuration server.
	ShardingTaskExecutorPoolMinSizeForConfigServers: int | *-1

	// (Sharding) Maximum time the mongos waits before attempting to heartbeat an idle connection in the pool.
	ShardingTaskExecutorPoolRefreshRequirementMS: int | *60000

	// (Sharding) Maximum time the mongos waits for a heartbeat before timing out.
	ShardingTaskExecutorPoolRefreshTimeoutMS: int | *20000

	// (Sharding) Allows starting a shard or config server member as a standalone for maintenance.
	skipShardingConfigurationChecks: bool | *false

	// (Storage) If true, new files created by MongoDB have permissions in accordance with the user's umask settings.
	honorSystemUmask: bool | *false

	// (Storage) Specify the interval in milliseconds between journal commits.
	journalCommitInterval: int & >=1 & <=500

	// (Storage) The minimum time window in seconds for which the storage engine keeps the snapshot history.
	minSnapshotHistoryWindowInSeconds: int & >=0 | *300

	// (Storage) Overrides the default permissions for groups and others when honorSystemUmask is false.
	processUmask: string

	// (Storage) Specifies the maximum number of concurrent read transactions (read tickets) allowed into the storage engine.
	storageEngineConcurrentReadTransactions: int

	// (Storage) Specifies the maximum number of concurrent write transactions allowed into the WiredTiger storage engine.
	storageEngineConcurrentWriteTransactions: int

	// (Storage) The interval in seconds when mongod flushes its working memory to disk.
	syncdelay: int | *60

	// (Storage) The initial delay before retrying a write operation that was rolled back due to cache pressure.
	temporarilyUnavailableBackoffBaseMs: int | *1000

	// (Storage) The maximum number of retries when a write operation is rolled back due to cache pressure.
	temporarilyUnavailableMaxRetries: int | *10

	// (Auditing) Enables the auditing of authorization successes for the authCheck action.
	auditAuthorizationSuccess: bool | *false

	// (Auditing) The interval, in seconds, for non-configured servers to poll a config server for the current audit generation.
	auditConfigPollingFrequencySecs: int | *300

	// (Auditing) Path and file name for logging metadata audit headers for audit log encryption.
	auditEncryptionHeaderMetadataFile: string

	// (Auditing) Enables audit log encryption for KMIP servers that only support KMIP protocol version 1.0 or 1.1.
	auditEncryptKeyWithKMIPGet: bool | *false

	// (Transaction) The maximum number of milliseconds for a session to be checked out when attempting to end an expired transaction.
	AbortExpiredTransactionsSessionCheckoutTimeout: int | *100

	// (Transaction) If true, the transaction coordinator returns a commit decision as soon as it is durable, without waiting for all shards to acknowledge.
	coordinateCommitReturnImmediatelyAfterPersistingDecision: bool | *false

	// (Transaction) Session limit for internal session metadata deletion.
	internalSessionsReapThreshold: int | *1000

	// (Transaction) The maximum time in milliseconds that multi-document transactions should wait to acquire locks.
	maxTransactionLockRequestTimeoutMillis: int | *5

	// (Transaction) The lifetime of multi-document transactions in seconds.
	transactionLifetimeLimitSeconds: int & >=1 | *60

	// (Transaction) The threshold value for retrying transactions that fail due to cache pressure.
	transactionTooLargeForCacheThreshold: float & >=0 & <=1.0 | *0.75

	// (Slot-Based Execution) Sets the size of the plan cache for the slot-based query execution engine.
	planCacheSize: string | *"5%"
}

#MongodParameter: {
	// The default log message verbosity level for components. The verbosity level determines the amount of Informational and Debug messages MongoDB outputs. 0 is the default level, to include Informational messages. 1 to 5 increases the verbosity level to include Debug messages.
	"systemLog.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Run mongod in a quiet mode that attempts to limit the amount of output. Not recommended for production systems.
	"systemLog.quiet": bool & true | false | *false

	// Print verbose information for debugging. Use for additional logging for support-related troubleshooting.
	"systemLog.traceAllExceptions": bool & true | false | *false

	// The facility level used when logging messages to syslog. The value you specify must be supported by your operating system's implementation of syslog. To use this option, you must set systemLog.destination to syslog.
	"systemLog.syslogFacility": string | *user

	// The path of the log file to which mongod should send all diagnostic logging information.
	"systemLog.path": string

	// When true, mongod appends new entries to the end of the existing log file when the instance restarts.
	"systemLog.logAppend": bool & true | false | *false

	// Determines the behavior for the logRotate command. Can be "rename" or "reopen".
	"systemLog.logRotate": string & "rename" | "reopen" | *"rename"

	// The destination to which MongoDB sends all log output. Can be "file" or "syslog". If unspecified, logs to standard output.
	"systemLog.destination": string & "file" | "syslog"

	// The time format for timestamps in log messages. Can be "iso8601-utc" or "iso8601-local".
	"systemLog.timeStampFormat": string & "iso8601-utc" | "iso8601-local" | *"iso8601-local"

	// Enable daemon mode that runs the process in the background. Not supported on Windows.
	"processManagement.fork": bool & true | false | *false

	// The file location to store the process ID (PID) of the mongod process.
	"processManagement.pidFilePath": string

	// The full path to the time zone database.
	"processManagement.timeZoneInfo": string

	// The service name when running as a Windows Service.
	"processManagement.windowsService.serviceName": string | *"MongoDB"

	// The name listed for MongoDB on the Services administrative application.
	"processManagement.windowsService.displayName": string | *"MongoDB"

	// The service description.
	"processManagement.windowsService.description": string | *"MongoDB Server"

	// The user context for the service. Must have "Log on as a service" privileges.
	"processManagement.windowsService.serviceUser": string

	// The password for the serviceUser.
	"processManagement.windowsService.servicePassword": string

	// The TCP port on which the MongoDB instance listens for client connections.
	"net.port": int | *27017

	// The hostnames and/or IP addresses on which mongod should listen.
	"net.bindIp": string | *"localhost"

	// If true, the instance binds to all IPv4 addresses. If ipv6 is also true, it binds to all IPv4 and IPv6 addresses.
	"net.bindIpAll": bool & true | false | *false

	// The maximum number of simultaneous connections.
	"net.maxIncomingConnections": int & 1000000 | 65536

	// When true, validates all requests from clients to prevent inserting malformed or invalid BSON.
	"net.wireObjectCheck": bool & true | false | *true

	// Enables or disables IPv6 support.
	"net.ipv6": bool & true | false | *false

	// Enable or disable listening on the UNIX domain socket.
	"net.unixDomainSocket.enabled": bool & true | false | *true

	// The path for the UNIX socket.
	"net.unixDomainSocket.pathPrefix": string | *"/tmp"

	// Sets the permission for the UNIX domain socket file.
	"net.unixDomainSocket.filePermissions": int | *0700

	// Comma-separated list of compressors to use. Can be snappy, zstd, zlib, or disabled.
	"net.compression.compressors": string | *"snappy,zstd,zlib"

	// Enables TLS for all network connections. Can be disabled, allowTLS, preferTLS, requireTLS.
	"net.tls.mode": string & "disabled" | "allowTLS" | "preferTLS" | "requireTLS"

	// The .pem file containing both the TLS certificate and key.
	"net.tls.certificateKeyFile": string

	// The password to decrypt the certificateKeyFile.
	"net.tls.certificateKeyFilePassword": string

	// Selects a certificate from the OS's certificate store. Can be specified by subject or thumbprint.
	"net.tls.certificateSelector": string

	// Selects a cluster certificate from the OS's certificate store. Can be specified by subject or thumbprint.
	"net.tls.clusterCertificateSelector": string

	// The .pem file for internal cluster authentication.
	"net.tls.clusterFile": string

	// The password to decrypt the clusterFile.
	"net.tls.clusterPassword": string

	// Specifies X.509 Distinguished Name attributes for cluster member authentication.
	"net.tls.clusterAuthX509.attributes": string

	// Specifies an extension value for cluster member authentication.
	"net.tls.clusterAuthX509.extensionValue": string

	// The .pem file containing the root certificate chain from the Certificate Authority.
	"net.tls.CAFile": string

	// The .pem file that contains the root certificate chain from the CA for validating client certificates.
	"net.tls.clusterCAFile": string

	// The .pem file containing the Certificate Revocation List.
	"net.tls.CRLFile": string

	// If true, clients are not required to provide a certificate.
	"net.tls.allowConnectionsWithoutCertificates": bool & true | false | *false

	// Disables validation checks for TLS certificates and allows invalid certificates.
	"net.tls.allowInvalidCertificates": bool & true | false | *false

	// Disables validation of hostnames in TLS certificates.
	"net.tls.allowInvalidHostnames": bool & true | false | *false

	// Comma-separated list of TLS protocols to disable. e.g., "TLS1_0,TLS1_1".
	"net.tls.disabledProtocols": string

	// Enables or disables FIPS mode.
	"net.tls.FIPSMode": bool & true | false | *false

	// Logs a message when a client connects using a specified TLS version.
	"net.tls.logVersions": string

	// The path to a key file for internal authentication.
	"security.keyFile": string

	// The authentication mode for cluster authentication. Can be keyFile, sendKeyFile, sendX509, x509.
	"security.clusterAuthMode": string & "keyFile" | "sendKeyFile" | "sendX509" | "x509" | *"keyFile"

	// Enables or disables Role-Based Access Control. Can be "enabled" or "disabled".
	"security.authorization": string & "enabled" | "disabled" | *"disabled"

	// Allows a mix of authenticated and non-authenticated connections for rolling upgrades.
	"security.transitionToAuth": bool & true | false | *false

	// Enables or disables server-side JavaScript execution.
	"security.javascriptEnabled": bool & true | false | *true

	// Redacts any message accompanying a given log event before logging.
	"security.redactClientLogData": bool & true | false | *false

	// A list of IP addresses/CIDR ranges for allowed authentication requests from other cluster members.
	"security.clusterIpSourceAllowlist": string[]

	// A fully qualified server domain name for SASL and Kerberos configuration.
	"security.sasl.hostName": string

	// Registered name of the service using SASL (e.g., for Kerberos).
	"security.sasl.serviceName": string | *"mongodb"

	// The path to the UNIX domain socket file for saslauthd.
	"security.sasl.saslauthdSocketPath": string

	// Enables encryption for the WiredTiger storage engine.
	"security.enableEncryption": bool & true | false | *false

	// The cipher mode for encryption at rest. Can be AES256-CBC or AES256-GCM.
	"security.encryptionCipherMode": string & "AES256-CBC" | "AES256-GCM" | *"AES256-CBC"

	// The path to the local keyfile for encryption at rest.
	"security.encryptionKeyFile": string

	// Unique KMIP identifier for an existing key.
	"security.kmip.keyIdentifier": string

	// If true, rotates the master key and re-encrypts the internal keystore.
	"security.kmip.rotateMasterKey": bool & true | false | *false

	// Hostname or IP address of the KMIP server.
	"security.kmip.serverName": string

	// Port number for the KMIP server.
	"security.kmip.port": string | *5696

	// Path to the .pem file to authenticate MongoDB to the KMIP server.
	"security.kmip.clientCertificateFile": string

	// The password to decrypt the clientCertificateFile.
	"security.kmip.clientCertificatePassword": string

	// Selects a client certificate from the OS's certificate store.
	"security.kmip.clientCertificateSelector": string

	// Path to the CA File for validating the KMIP server.
	"security.kmip.serverCAFile": string

	// How many times to retry the initial connection to the KMIP server.
	"security.kmip.connectRetries": int | *0

	// Timeout in milliseconds to wait for a response from the KMIP server.
	"security.kmip.connectTimeoutMS": int | *5000

	// Activates all newly created KMIP keys upon creation.
	"security.kmip.activateKeys": bool & true | false | *true

	// Frequency in seconds to poll the KMIP server for active keys.
	"security.kmip.keyStatePollingSeconds": int | *900

	// When true, uses KMIP protocol version 1.0 or 1.1.
	"security.kmip.useLegacyProtocol": bool & true | false | *false

	// Comma-delimited list of LDAP servers to connect to.
	"security.ldap.servers": string

	// The identity with which to bind to the LDAP server for queries.
	"security.ldap.bind.queryUser": string

	// The password for the queryUser.
	"security.ldap.bind.queryPassword": string

	// Allows binding using Windows login credentials. (Windows only)
	"security.ldap.bind.useOSDefaults": bool & true | false | *false

	// The method to use for authentication. Can be "simple" or "sasl".
	"security.ldap.bind.method": string & "simple" | "sasl" | *"simple"

	// Comma-separated list of SASL mechanisms.
	"security.ldap.bind.saslMechanisms": string | *"DIGEST-MD5"

	// Transport security for LDAP connection. Can be "tls" or "none".
	"security.ldap.transportSecurity": string & "tls" | "none" | *"tls"

	// Timeout in milliseconds for LDAP operations.
	"security.ldap.timeoutMS": int | *10000

	// Number of retries after a network error.
	"security.ldap.retryCount": int | *0

	// An ordered array of documents for mapping a username to an LDAP DN.
	"security.ldap.userToDNMapping": string

	// A relative LDAP query URL to retrieve a user's groups.
	"security.ldap.authz.queryTemplate": string

	// If true, checks the availability of the LDAP server on startup.
	"security.ldap.validateLDAPServerConfig": bool & true | false | *true

	// A container for setting various MongoDB parameters.
	"setParameter": #MongodSetParamParameter

	// The directory where the mongod instance stores its data.
	"storage.dbPath": string | *"/data/db"

	// Maximum time in milliseconds between journal operations.
	"storage.journal.commitIntervalMs": number & 1-500 | *100

	// If true, MongoDB uses a separate directory for each database.
	"storage.directoryPerDB": bool & true | false | *false

	// The amount of time in seconds that can pass before MongoDB flushes data to data files.
	"storage.syncPeriodSecs": number | *60

	// The storage engine for the database. Can be "wiredTiger" or "inMemory".
	"storage.engine": string & "wiredTiger" | "inMemory" | *"wiredTiger"

	// Minimum number of hours to preserve an oplog entry.
	"storage.oplogMinRetentionHours": double | *0

	// Maximum size of the WiredTiger internal cache in GB.
	"storage.wiredTiger.engineConfig.cacheSizeGB": float

	// Default compressor for the journal data. Can be none, snappy, zlib, zstd.
	"storage.wiredTiger.engineConfig.journalCompressor": string & "none" | "snappy" | "zlib" | "zstd" | *"snappy"

	// If true, stores indexes and collections in separate subdirectories.
	"storage.wiredTiger.engineConfig.directoryForIndexes": bool & true | false | *false

	// The maximum size of an overflow file for the WiredTiger cache in GB.
	"storage.wiredTiger.engineConfig.maxCacheOverflowFileSizeGB": number

	// The compression level for zstd.
	"storage.wiredTiger.engineConfig.zstdCompressionLevel": int & 1-22 | *6

	// Default compression for collection data. Can be none, snappy, zlib, zstd.
	"storage.wiredTiger.collectionConfig.blockCompressor": string & "none" | "snappy" | "zlib" | "zstd" | *"snappy"

	// Enables or disables prefix compression for index data.
	"storage.wiredTiger.indexConfig.prefixCompression": bool & true | false | *true

	// Maximum amount of memory in GB to allocate for in-memory data.
	"storage.inMemory.engineConfig.inMemorySizeGB": float

	// Specifies which operations should be profiled. Can be off, slowOp, all.
	"operationProfiling.mode": string & "off" | "slowOp" | "all" | *"off"

	// The slow operation time threshold in milliseconds.
	"operationProfiling.slowOpThresholdMs": int | *100

	// The fraction of slow operations (0.0-1.0) that should be profiled or logged.
	"operationProfiling.slowOpSampleRate": double | *1.0

	// A filter expression that controls which operations are profiled and logged.
	"operationProfiling.filter": string

	// The maximum size in megabytes for the oplog.
	"replication.oplogSizeMB": int

	// The name of the replica set.
	"replication.replSetName": string

	// Enables support for "majority" read concern. Always true in MongoDB 5.0+.
	"replication.enableMajorityReadConcern": bool & true | *true

	// The role of the mongod instance in a sharded cluster. Can be "configsvr" or "shardsvr".
	"sharding.clusterRole": string & "configsvr" | "shardsvr"

	// If true, a shard archives documents from chunks that it migrates to other shards.
	"sharding.archiveMovedChunks": bool & true | false | *false

	// Specifies the unique identifier of the KMIP key for audit log encryption.
	"auditLog.auditEncryptionKeyIdentifier": string

	// Specifies the compression mode for audit log encryption. Can be "zstd" or "none".
	"auditLog.compressionMode": string & "zstd" | "none" | *"none"

	// Enables auditing and specifies the destination. Can be syslog, console, file.
	"auditLog.destination": string & "syslog" | "console" | "file"

	// A filter to limit the types of operations the audit system records.
	"auditLog.filter": string

	// The format of the output file. Can be JSON or BSON.
	"auditLog.format": string & "JSON" | "BSON"

	// Specifies the path and file name for a local audit key file for audit log encryption.
	"auditLog.localAuditKeyFile": string

	// The output file for auditing if destination is "file".
	"auditLog.path": string

	// If true, allows runtime configuration of audit filters.
	"auditLog.runtimeConfiguration": bool

	// Specifies the format used for audit logs. Can be "mongo" or "OCSF".
	"auditLog.schema": string & "mongo" | "OCSF" | *"mongo"
}

configuration: #MongodParameter & {}
