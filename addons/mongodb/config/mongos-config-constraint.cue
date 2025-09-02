#MongosSetParameterParams: {
	// (Authentication) Allows or disallows the retrieval of authorization roles from client X.509 certificates.
	allowRolesFromX509Certificates: bool & *true

	// (Authentication) A comma-separated list of authentication mechanisms the server accepts.
	authenticationMechanisms: string

	// (Authentication) The number of milliseconds to wait before informing clients that their authentication attempt has failed.
	authFailedDelayMs: int & >=0 & <=5000 & *0

	// (Authentication) Maximum number of retries for AWS IAM authentication after a connection failure.
	awsSTSRetryCount: int & *2

	// (Authentication) The mode for cluster member authentication, used for rolling upgrades to x509.
	clusterAuthMode: string & ("sendX509" | "x509")

	// (Authentication) Enables or disables the localhost authentication bypass.
	enableLocalhostAuthBypass: bool & *true

	// (Authentication) Disables the O/OU/DC check when clusterAuthMode is keyFile, allowing member certificates to authenticate as users in $external.
	enforceUserClusterSeparation: bool

	// (Authentication) The number of seconds for which an HMAC signing key is valid before rotating to the next one.
	KeysRotationIntervalSec: int & *7776000

	// (Authentication) Enables or disables OCSP on Linux and macOS.
	ocspEnabled: bool & *true

	// (Authentication) The number of seconds to wait before refreshing the stapled OCSP status response.
	ocspStaplingRefreshPeriodSecs: int & >=1

	// (Authentication) Specifies the cipher string for OpenSSL when using TLS 1.2 or earlier.
	opensslCipherConfig: string

	// (Authentication) Specifies the list of supported cipher suites OpenSSL should permit when using TLS 1.3 encryption.
	opensslCipherSuiteConfig: string

	// (Authentication) Specifies the path to the PEM file that contains the OpenSSL Diffie-Hellman parameters.
	opensslDiffieHellmanParameters: string

	// (Authentication) Instructs the server to check the connectivity of accepted connections before processing them. (Linux Only)
	pessimisticConnectivityCheckForAcceptedConnections: bool & *false

	// (Authentication) Specifies the path to the Unix Domain Socket of the saslauthd instance for proxy authentication.
	saslauthdPath: string

	// (Authentication) Overrides MongoDB's default hostname detection for configuring SASL and Kerberos.
	saslHostName: string

	// (Authentication) Overrides the default Kerberos service name component of the Kerberos principal name. Unspecified default is "mongodb".
	saslServiceName: string

	// (Authentication) Changes the number of hashing iterations used for all new SCRAM-SHA-1 passwords.
	scramIterationCount: int & >=5000 & *10000

	// (Authentication) Changes the number of hashing iterations used for all new SCRAM-SHA-256 passwords.
	scramSHA256IterationCount: int & >=5000 & *15000

	// (Authentication) Sets the SSL mode, useful during a rolling upgrade to TLS/SSL to minimize downtime.
	sslMode: string & ("preferSSL" | "requireSSL")

	// (Authentication) Overrides the net.tls.clusterAuthX509 configuration options.
	tlsClusterAuthX509Override: string

	// (Authentication) Sets the TLS mode, useful during a rolling upgrade to TLS/SSL to minimize downtime.
	tlsMode: string & ("preferTLS" | "requireTLS")

	// (Authentication) The maximum number of seconds the instance should wait to receive the OCSP status response for its certificates. If unset, uses the tlsOCSPVerifyTimeoutSecs value.
	tlsOCSPStaplingTimeoutSecs: int & >=1

	// (Authentication) The maximum number of seconds that the instance should wait for the OCSP response when verifying server certificates.
	tlsOCSPVerifyTimeoutSecs: int & >=1 & *5

	// (Authentication) Directs the instance to withhold sending its TLS certificate during intra-cluster communications.
	tlsWithholdClientCertificate: bool & *false

	// (Authentication) An alternative Distinguished Name (DN) the instance can use to identify members of the deployment.
	tlsX509ClusterAuthDNOverride: string

	// (Authentication) Controls the warning threshold in days for X.509 certificate expiration.
	tlsX509ExpirationWarningThresholdDays: int & >=0 & *30

	// (Authentication) Specifies the interval (in seconds) at which the mongos instance checks for stale user cache data and clears it.
	userCacheInvalidationIntervalSecs: int & >=1 & <=86400 & *30

	// (General) Sets the maximum size of the legacy connection pools for outgoing connections to other mongod instances.
	connPoolMaxConnsPerHost: int & *200

	// (General) Sets the maximum number of in-use connections for the legacy global connection pool.
	connPoolMaxInUseConnsPerHost: int

	// (General) Sets the expiration threshold in milliseconds for idle cursors.
	cursorTimeoutMillis: int & *600000

	// (General) Allows a server receiving a step up/down request to terminate if it cannot comply within the timeout (in seconds).
	fassertOnLockTimeoutForStepUpDown: int & *15

	// (General) Sets the time limit that connections in the legacy global connection pool can remain idle.
	globalConnPoolIdleTimeoutMinutes: int

	// (General) Adds more verbose tracing for curl on Linux and macOS. Unset by default.
	httpVerboseLogging: bool

	// (General) Sets the time limit in milliseconds to log the establishment of slow server connections.
	slowConnectionThresholdMillis: int & *100

	// (General) Enables a background thread that periodically releases memory back to the operating system.
	tcmallocEnableBackgroundThread: bool & *true

	// (General) Specifies the minimum rate at which TCMalloc releases unused memory to the system (bytes per second).
	tcmallocReleaseRate: float & *0.0

	// (General) Enables support for outbound TCP Fast Open (TFO) connections on Linux.
	tcpFastOpenClient: bool & *true

	// (General) Sets the size of the queue for pending TCP Fast Open (TFO) connections.
	tcpFastOpenQueueSize: int & *1024

	// (General) Enables support for accepting inbound TCP Fast Open (TFO) connections.
	tcpFastOpenServer: bool & *true

	// (Logging) Determines whether to enable specific log messages related to cluster connection health metrics.
	enableDetailedConnectionHealthMetricLogLines: bool & *true

	// (Logging) Sets the verbosity levels of various components for log messages.
	logComponentVerbosity: {...}

	// (Logging) Specifies an integer between 0 and 5 signifying the verbosity of the logging, where 5 is the most verbose.
	logLevel: int & >=0 & <=5 & *0

	// (Logging) Specifies the maximum size, in kilobytes, for an individual attribute field in a log entry before truncation.
	maxLogSizeKB: int & >=0 & *10

	// (Logging) Sets quiet logging mode, which suppresses certain log events like connections and drop commands.
	quiet: bool

	// (Logging) Redacts any message accompanying a given log event before logging to prevent writing sensitive data.
	redactClientLogData: bool

	// (Logging) Redacts field values of encrypted Binary data from all log messages.
	redactEncryptedFields: bool & *true

	// (Logging) Suppresses warnings logged when clients connect without a TLS certificate.
	suppressNoTLSPeerCertificateWarning: bool & *false



	// (Logging) Configures mongos to log full source code stack traces for debugging.
	traceExceptions: bool

	// (Diagnostic) Specify the directory for the diagnostic directory for mongos.
	diagnosticDataCollectionDirectoryPath: string

	// (Diagnostic) Specifies the maximum size in megabytes of the diagnostic.data directory.
	diagnosticDataCollectionDirectorySizeMB: int & *500

	// (Diagnostic) Determines whether to enable the collecting and logging of data for diagnostic purposes.
	diagnosticDataCollectionEnabled: bool & *true

	// (Diagnostic) Specifies the maximum size in megabytes of each diagnostic file.
	diagnosticDataCollectionFileSizeMB: int & *10

	// (Diagnostic) Specifies the interval in milliseconds at which to collect diagnostic data.
	diagnosticDataCollectionPeriodMillis: int & *1000

	// (Replication and Consistency) Sets the connection timeout in milliseconds for the replica set monitor.
	connectTimeoutMs: int & >=500 & *10000

	// (Replication and Consistency) Allows using IP addresses instead of hostnames in replica set configurations, bypassing the split-horizon DNS check.
	disableSplitHorizonIPCheck: bool & *false

	// (Replication and Consistency) Enables or disables the mechanism that controls the rate at which the primary applies its writes to keep secondaries from lagging.
	enableFlowControl: bool & *true

	// (Replication and Consistency) Allows secondary members to replicate from other secondaries even if settings.chainingAllowed is false.
	enableOverrideClusterChainingSetting: bool & *false

	// (Replication and Consistency) The target maximum 'majority committed' lag in seconds when running with flow control.
	flowControlTargetLagSeconds: int & >0 & *10

	// (Replication and Consistency) The amount of time to wait to log a warning once the flow control mechanism detects the majority commit point has not moved.
	flowControlWarnThresholdSeconds: int & >=0 & *10

	// (Replication and Consistency) How long in milliseconds to wait between hello requests or RTT measurements.
	heartBeatFrequencyMs: int & >=500 & *10000

	// (Replication and Consistency) The time in minutes that a session remains active after its most recent use. For testing only.
	localLogicalSessionTimeoutMinutes: int & *30

	// (Replication and Consistency) Defines the length of the latency window in milliseconds used in server selection.
	localThresholdMs: int & >=0 & *15

	// (Replication and Consistency) The interval (in milliseconds) at which the cache refreshes its logical session records.
	logicalSessionRefreshMillis: int & *300000

	// (Replication and Consistency) The maximum amount in seconds by which the current cluster time can be advanced.
	maxAcceptableLogicalClockDriftSecs: int & *31536000

	// (Replication and Consistency) The maximum number of sync source changes per hour before a node temporarily stops re-evaluating.
	maxNumSyncSourceChangesPerHour: int & *3

	// (Replication and Consistency) The maximum number of sessions that can be cached.
	maxSessions: int & *1000000

	// (Replication and Consistency) The number of milliseconds to delay applying batches of oplog operations on secondary nodes.
	oplogBatchDelayMillis: int & >=0 & *0

	// (Replication and Consistency) Sets the maximum oplog application batch size in bytes.
	replBatchLimitBytes: int & >=16777216 & <=104857600 & *104857600

	// (Replication and Consistency) Determines which replica set monitor protocol to use.
	replicaSetMonitorProtocol: string & ("streamable" | "sdam") & *"streamable"

	// (Sharding) Maximum number of entries allowed in the catalog cache for collections.
	catalogCacheCollectionMaxEntries: int & *10000

	// (Sharding) Maximum number of entries allowed in the catalog cache for databases.
	catalogCacheDatabaseMaxEntries: int & *10000

	// (Sharding) Maximum number of entries allowed in the catalog cache for indexes.
	catalogCacheIndexMaxEntries: int & *10000

	// (Sharding) The minimum time period (in milliseconds) between consecutive split and merge commands run by the balancer.
	chunkDefragmentationThrottlingMS: int & >=0 & *0

	// (Sharding) Deprecated in 8.0. Allows the catalog cache to be refreshed only if the shard needs it.
	enableFinerGrainedCatalogCacheRefresh: bool & *true

	// (Sharding) The timeout in milliseconds for find operations on the config.chunks collection.
	findChunksOnConfigTimeoutMS: int & >=0 & *900000

	// (Sharding) Configures a mongos instance to preload the routing table for a sharded cluster on startup.
	loadRoutingTableOnStartup: bool & *true

	// (Sharding) Deprecated in 8.0. The maximum time limit (in milliseconds) for a hedged read.
	maxTimeMSForHedgedReads: int & *150

	// (Sharding) Specifies the time (in milliseconds) to wait for ongoing operations to complete before shutting down mongos in response to a SIGTERM signal.
	mongosShutdownTimeoutMillisForSignaledShutdown: int & *15000

	// (Sharding) Determines whether mongos performs opportunistic reads against replica set secondaries.
	opportunisticSecondaryTargeting: bool & *false

	// (Sharding) Interval that a sampler (mongos) refreshes its query analyzer sample rates.
	queryAnalysisSamplerConfigurationRefreshSecs: int & *10

	// (Sharding) Deprecated in 8.0. Specifies whether mongos supports hedged reads.
	readHedgingMode: string & ("on" | "off") & *"on"

	// (Sharding) Specifies the size of the routing table cache buckets used to implement chunk grouping optimization.
	routingTableCacheChunkBucketSize: int & >0 & *500

	// (Sharding) Maximum time mongos goes without communication to a host before it drops all connections to the host.
	ShardingTaskExecutorPoolHostTimeoutMS: int & *300000

	// (Sharding) Maximum number of simultaneous initiating connections each TaskExecutor connection pool can have to a mongod instance.
	ShardingTaskExecutorPoolMaxConnecting: int & *2

	// (Sharding) Maximum number of outbound connections each TaskExecutor connection pool can open to any given mongod instance (2^64 - 1).
	ShardingTaskExecutorPoolMaxSize: int & *18446744073709551615

	// (Sharding) Optional override for ShardingTaskExecutorPoolMaxSize for connections to a configuration server.
	ShardingTaskExecutorPoolMaxSizeForConfigServers: int & *-1

	// (Sharding) Minimum number of outbound connections each TaskExecutor connection pool can open to any given mongod instance.
	ShardingTaskExecutorPoolMinSize: int & *1

	// (Sharding) Optional override for ShardingTaskExecutorPoolMinSize for connections to a configuration server.
	ShardingTaskExecutorPoolMinSizeForConfigServers: int & *-1

	// (Sharding) Maximum time the mongos waits before attempting to heartbeat an idle connection in the pool.
	ShardingTaskExecutorPoolRefreshRequirementMS: int & *60000

	// (Sharding) Maximum time the mongos waits for a heartbeat before timing out.
	ShardingTaskExecutorPoolRefreshTimeoutMS: int & *20000

	// (Sharding) The number of Task Executor connection pools to use for a given mongos.
	taskExecutorPoolSize: int & *1

	// (Sharding) Configures a mongos instance to prewarm its connection pool on startup.
	warmMinConnectionsInShardingTaskExecutorPoolOnStartup: bool & *true

	// (Sharding) Sets the timeout in milliseconds for a mongos to wait for minimum connections to be established on startup.
	warmMinConnectionsInShardingTaskExecutorPoolOnStartupWaitMS: int & *2000

	// (Health Manager) The amount of time (in seconds) to wait from a Health Manager failure until the mongos is removed from the cluster.
	activeFaultDurationSecs: int

	// (Health Manager) Sets intensity levels (critical, non-critical, off) for Health Manager facets (configServer, dns, ldap).
	healthMonitoringIntensities: [...{...}]

	// (Health Manager) Sets the check interval in milliseconds for each Health Manager facet.
	healthMonitoringIntervals: [...{...}]

	// (Health Manager) Configures the Progress Monitor to ensure Health Manager checks are not stuck.
	progressMonitor: {
		interval: int
		deadline: int
	}

	// (Storage) Maximum number of retry attempts when an upsert operation encounters a duplicate key error.
	upsertMaxRetryAttemptsOnDuplicateKeyError: int & *100

	// (Auditing) Enables the auditing of authorization successes for the authCheck action.
	auditAuthorizationSuccess: bool & *false

	// (Auditing) The interval in seconds for non-configured servers to poll a config server for the current audit generation.
	auditConfigPollingFrequencySecs: int & *300

	// (Auditing) Path and file name for logging metadata audit headers for audit log encryption.
	auditEncryptionHeaderMetadataFile: string

	// (Auditing) Enables audit log encryption for KMIP servers that only support KMIP protocol version 1.0 or 1.1.
	auditEncryptKeyWithKMIPGet: bool & *false

	// (Transaction) Session limit for internal session metadata deletion.
	internalSessionsReapThreshold: int & *1000
}

#MongosParameter: {
	// The default log message verbosity level for components. The verbosity level determines the amount of Informational and Debug messages MongoDB outputs. 0 is the default level, to include Informational messages. 1 to 5 increases the verbosity level to include Debug messages.
	"systemLog.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Run mongos in a quiet mode that attempts to limit the amount of output. Not recommended for production systems.
	"systemLog.quiet": bool & true | false | *false

	// Print verbose information for debugging. Use for additional logging for support-related troubleshooting.
	"systemLog.traceAllExceptions": bool & true | false | *false

	// The facility level used when logging messages to syslog. The value you specify must be supported by your operating system's implementation of syslog. To use this option, you must set systemLog.destination to syslog.
	"systemLog.syslogFacility": string | *"user"

	// The path of the log file to which mongos should send all diagnostic logging information.
	"systemLog.path": string

	// When true, mongos appends new entries to the end of the existing log file when the instance restarts.
	"systemLog.logAppend": bool & true | false | *false

	// Determines the behavior for the logRotate command. Can be "rename" or "reopen".
	"systemLog.logRotate": string & "rename" | "reopen" | *"rename"

	// The destination to which MongoDB sends all log output. Can be "file" or "syslog". If unspecified, logs to standard output.
	"systemLog.destination": string & "file" | "syslog"

	// The time format for timestamps in log messages. Can be "iso8601-utc" or "iso8601-local".
	"systemLog.timeStampFormat": string & "iso8601-utc" | "iso8601-local" | *"iso8601-local"

	// Verbosity level for assertion-related components.
	"systemLog.component.assert.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for access control related components.
	"systemLog.component.accessControl.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for command-related components.
	"systemLog.component.command.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for control-related components.
	"systemLog.component.control.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for diagnostic data collection (FTDC) components.
	"systemLog.component.ftdc.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for geospatial parsing components.
	"systemLog.component.geo.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for indexing components.
	"systemLog.component.index.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for networking components.
	"systemLog.component.network.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for query components.
	"systemLog.component.query.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for rejected query operations.
	"systemLog.component.query.rejected.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for $queryStats components.
	"systemLog.component.queryStats.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for replication components.
	"systemLog.component.replication.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for election components.
	"systemLog.component.replication.election.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for heartbeats components.
	"systemLog.component.replication.heartbeats.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for initialSync components.
	"systemLog.component.replication.initialSync.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for rollback components.
	"systemLog.component.replication.rollback.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for sharding components.
	"systemLog.component.sharding.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for storage components.
	"systemLog.component.storage.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for journaling components.
	"systemLog.component.storage.journal.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for recovery components.
	"systemLog.component.storage.recovery.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for WiredTiger components.
	"systemLog.component.storage.wt.verbosity": int & -1 | 0 | 1 | 2 | 3 | 4 | 5 | *-1

	// Verbosity level for WiredTiger backup operations.
	"systemLog.component.storage.wt.wtBackup.verbosity": int & -1 | 0 | 1 | 2 | 3 | 4 | 5 | *-1

	// Verbosity level for WiredTiger checkpoint operations.
	"systemLog.component.storage.wt.wtCheckpoint.verbosity": int & -1 | 0 | 1 | 2 | 3 | 4 | 5 | *-1

	// Verbosity level for WiredTiger compaction operations.
	"systemLog.component.storage.wt.wtCompact.verbosity": int & -1 | 0 | 1 | 2 | 3 | 4 | 5 | *-1

	// Verbosity level for WiredTiger eviction operations.
	"systemLog.component.storage.wt.wtEviction.verbosity": int & -1 | 0 | 1 | 2 | 3 | 4 | 5 | *-1

	// Verbosity level for WiredTiger history store operations.
	"systemLog.component.storage.wt.wtHS.verbosity": int & -1 | 0 | 1 | 2 | 3 | 4 | 5 | *-1

	// Verbosity level for WiredTiger recovery operations.
	"systemLog.component.storage.wt.wtRecovery.verbosity": int & -1 | 0 | 1 | 2 | 3 | 4 | 5 | *-1

	// Verbosity level for WiredTiger rollback to stable operations.
	"systemLog.component.storage.wt.wtRTS.verbosity": int & -1 | 0 | 1 | 2 | 3 | 4 | 5 | *-1

	// Verbosity level for WiredTiger salvage operations.
	"systemLog.component.storage.wt.wtSalvage.verbosity": int & -1 | 0 | 1 | 2 | 3 | 4 | 5 | *-1

	// Verbosity level for WiredTiger timestamp operations.
	"systemLog.component.storage.wt.wtTimestamp.verbosity": int & -1 | 0 | 1 | 2 | 3 | 4 | 5 | *-1

	// Verbosity level for WiredTiger transaction operations.
	"systemLog.component.storage.wt.wtTransaction.verbosity": int & -1 | 0 | 1 | 2 | 3 | 4 | 5 | *-1

	// Verbosity level for WiredTiger verification operations.
	"systemLog.component.storage.wt.wtVerify.verbosity": int & -1 | 0 | 1 | 2 | 3 | 4 | 5 | *-1

	// Verbosity level for WiredTiger log write operations.
	"systemLog.component.storage.wt.wtWriteLog.verbosity": int & -1 | 0 | 1 | 2 | 3 | 4 | 5 | *-1

	// Verbosity level for transaction components.
	"systemLog.component.transaction.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Verbosity level for write operation components.
	"systemLog.component.write.verbosity": int & 0 | 1 | 2 | 3 | 4 | 5 | *0

	// Enable daemon mode that runs the process in the background. Not supported on Windows.
	"processManagement.fork": bool & true | false | *false

	// The file location to store the process ID (PID) of the mongos process.
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

	// The hostnames and/or IP addresses on which mongos should listen.
	"net.bindIp": string | *"localhost"

	// If true, the instance binds to all IPv4 addresses. If ipv6 is also true, it binds to all IPv4 and IPv6 addresses.
	"net.bindIpAll": bool & true | false | *false

	// The maximum number of simultaneous connections. *Default on Windows: 1,000,000. Default on Linux: 80% of RLIMIT_NOFILE.
	"net.maxIncomingConnections": int

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

	// Enables or disables FIPS mode. (Enterprise Only)
	"net.tls.FIPSMode": bool & true | false | *false

	// Logs a message when a client connects using a specified TLS version.
	"net.tls.logVersions": string

	// The path to a key file for internal authentication.
	"security.keyFile": string

	// The authentication mode for cluster authentication. Can be keyFile, sendKeyFile, sendX509, x509.
	"security.clusterAuthMode": string & "keyFile" | "sendKeyFile" | "sendX509" | "x509" | *"keyFile"

	// Allows a mix of authenticated and non-authenticated connections for rolling upgrades.
	"security.transitionToAuth": bool & true | false | *false

	// Enables or disables server-side JavaScript execution.
	"security.javascriptEnabled": bool & true | false | *true

	// Redacts any message accompanying a given log event before logging. (Enterprise Only)
	"security.redactClientLogData": bool & true | false | *false

	// A list of IP addresses/CIDR ranges for allowed authentication requests from other cluster members.
	"security.clusterIpSourceAllowlist": [...string]

	// A fully qualified server domain name for SASL and Kerberos configuration.
	"security.sasl.hostName": string

	// Registered name of the service using SASL (e.g., for Kerberos). (Enterprise Only)
	"security.sasl.serviceName": string | *"mongodb"

	// The path to the UNIX domain socket file for saslauthd.
	"security.sasl.saslauthdSocketPath": string

	// Comma-delimited list of LDAP servers to connect to. (Enterprise Only)
	"security.ldap.servers": string

	// The identity with which to bind to the LDAP server for queries. (Enterprise Only)
	"security.ldap.bind.queryUser": string

	// The password for the queryUser. (Enterprise Only)
	"security.ldap.bind.queryPassword": string

	// Allows binding using Windows login credentials. (Windows only, Enterprise Only)
	"security.ldap.bind.useOSDefaults": bool & true | false | *false

	// The method to use for authentication. Can be "simple" or "sasl". (Enterprise Only)
	"security.ldap.bind.method": string & "simple" | "sasl" | *"simple"

	// Comma-separated list of SASL mechanisms. (Enterprise Only)
	"security.ldap.bind.saslMechanisms": string | *"DIGEST-MD5"

	// Transport security for LDAP connection. Can be "tls" or "none". (Enterprise Only)
	"security.ldap.transportSecurity": string & "tls" | "none" | *"tls"

	// Timeout in milliseconds for LDAP operations. (Enterprise Only)
	"security.ldap.timeoutMS": int | *10000

	// Number of retries after a network error. (Enterprise Only)
	"security.ldap.retryCount": int | *0

	// An ordered array of documents for mapping a username to an LDAP DN. (Enterprise Only)
	"security.ldap.userToDNMapping": string

	// A relative LDAP query URL to retrieve a user's groups. (Enterprise Only)
	"security.ldap.authz.queryTemplate": string

	// If true, checks the availability of the LDAP server on startup. (Enterprise Only)
	"security.ldap.validateLDAPServerConfig": bool & true | false | *true

	// A container for setting various MongoDB parameters. e.g., setParameter: { featureFlag: "..." }
	"setParameter": #MongosSetParameterParams

	// Specifies which operations should be logged. For mongos, this only affects the diagnostic log. Can be off, slowOp, all.
	"operationProfiling.mode": string & "off" | "slowOp" | "all" | *"off"

	// The slow operation time threshold in milliseconds for the diagnostic log.
	"operationProfiling.slowOpThresholdMs": int | *100

	// The fraction of slow operations (0.0-1.0) that should be logged.
	"operationProfiling.slowOpSampleRate": float | *1.0

	// A filter expression that controls which operations are logged.
	"operationProfiling.filter": string

	// The ping time in milliseconds for mongos to select secondary members for reads. (mongos only)
	"replication.localPingThresholdMs": int | *15

	// The config server replica set connection string. (mongos only, required)
	"sharding.configDB": string

	// Enables auditing and specifies the destination. Can be syslog, console, file. (Enterprise Only)
	"auditLog.destination": string & "syslog" | "console" | "file"

	// The format of the output file. Can be JSON or BSON. (Enterprise Only)
	"auditLog.format": string & "JSON" | "BSON"

	// The output file for auditing if destination is "file". (Enterprise Only)
	"auditLog.path": string

	// A filter to limit the types of operations the audit system records. (Enterprise Only)
	"auditLog.filter": string

	// If true, allows runtime configuration of audit filters. (Enterprise Only)
	"auditLog.runtimeConfiguration": bool

	// Specifies the format used for audit logs. Can be "mongo" or "OCSF". (Enterprise Only)
	"auditLog.schema": string & "mongo" | "OCSF" | *"mongo"
}

configuration: #MongosParameter & {}

