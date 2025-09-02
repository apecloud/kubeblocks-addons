# mongod.conf
# for documentation of all options, see:
#   http://docs.mongodb.org/manual/reference/configuration-options/

# TODO: .Values.dataMountPath
{{- $mongodb_root := "/data/mongodb" }}
{{- $mongodb_port := $.KB_SERVICE_PORT }}

# mongod default configuration file
# This file contains the default settings for a mongod instance.
# Uncomment and modify parameters as needed for your deployment.

#----------------------------------------------------------------------
# 1. Storage
#----------------------------------------------------------------------
storage:
  # The directory where the mongod instance stores its data.
  # Default: /data/db on Linux/macOS, \data\db on Windows.
  dbPath: {{ $mongodb_root }}/db

  # The storage engine for the database.
  # Options: "wiredTiger", "inMemory"
  engine: "wiredTiger"

  # If true, MongoDB uses a separate directory for each database.
  directoryPerDB: true

  # The amount of time in seconds that can pass before MongoDB flushes data to data files.
  syncPeriodSecs: 60

  # Settings for the journal.
  journal:
    # Maximum time in milliseconds between journal operations.
    commitIntervalMs: 100

  # WiredTiger storage engine specific options.
  wiredTiger:
    engineConfig:
      # Default compressor for the journal data.
      # Options: "none", "snappy", "zlib", "zstd"
      journalCompressor: "snappy"
      # If true, stores indexes and collections in separate subdirectories.
      directoryForIndexes: false
      # The compression level for zstd.
      zstdCompressionLevel: 6
    collectionConfig:
      # Default compression for collection data.
      # Options: "none", "snappy", "zlib", "zstd"
      blockCompressor: "snappy"
    indexConfig:
      # Enables or disables prefix compression for index data.
      prefixCompression: true

  # Minimum number of hours to preserve an oplog entry.
  oplogMinRetentionHours: 0

#----------------------------------------------------------------------
# 2. System Log
#----------------------------------------------------------------------
systemLog:
  # The default log message verbosity level for components.
  # 0 is the default level (Informational), 1-5 increases verbosity (Debug).
  verbosity: 0

  # The destination to which MongoDB sends all log output.
  # Options: "file", "syslog". If unspecified, logs to standard output.
  destination: file

  # The path of the log file to which mongod should send all diagnostic logging information.
  path: {{ $mongodb_root }}/log/mongod.log

  # When true, mongod appends new entries to the end of the existing log file when the instance restarts.
  logAppend: false

  # The time format for timestamps in log messages.
  # Options: "iso8601-utc", "iso8601-local"
  timeStampFormat: "iso8601-local"

  # Run mongod in a quiet mode that attempts to limit the amount of output.
  quiet: false

  # Print verbose information for debugging.
  traceAllExceptions: false

  # The facility level used when logging messages to syslog.
  syslogFacility: "user"

  # Determines the behavior for the logRotate command.
  # Options: "rename", "reopen"
  logRotate: "rename"

  # Verbosity levels for various components.
  component:
    assert:
      verbosity: 0
    accessControl:
      verbosity: 0
    command:
      verbosity: 0
    control:
      verbosity: 0
    ftdc:
      verbosity: 0
    geo:
      verbosity: 0
    index:
      verbosity: 0
    network:
      verbosity: 0
    query:
      verbosity: 0
      rejected:
        verbosity: 0
    queryStats:
      verbosity: 0
    replication:
      verbosity: 0
      election:
        verbosity: 0
      heartbeats:
        verbosity: 0
      initialSync:
        verbosity: 0
      rollback:
        verbosity: 0
    sharding:
      verbosity: 0
    storage:
      verbosity: 0
      journal:
        verbosity: 0
      recovery:
        verbosity: 0
      wt:
        verbosity: -1
        wtBackup:
          verbosity: -1
        wtCheckpoint:
          verbosity: -1
        wtCompact:
          verbosity: -1
        wtEviction:
          verbosity: -1
        wtHS:
          verbosity: -1
        wtRecovery:
          verbosity: -1
        wtRTS:
          verbosity: -1
        wtSalvage:
          verbosity: -1
        wtTimestamp:
          verbosity: -1
        wtTransaction:
          verbosity: -1
        wtVerify:
          verbosity: -1
        wtWriteLog:
          verbosity: -1
    transaction:
      verbosity: 0
    write:
      verbosity: 0

#----------------------------------------------------------------------
# 3. Network
#----------------------------------------------------------------------
net:
  # The TCP port on which the MongoDB instance listens for client connections.
  port: {{ $mongodb_port }}

  # The hostnames and/or IP addresses on which mongod should listen.
  # bindIp: localhost

  # If true, the instance binds to all IPv4 addresses.
  bindIpAll: true

  # When true, validates all requests from clients to prevent inserting malformed or invalid BSON.
  wireObjectCheck: true

  # Enables or disables IPv6 support.
  ipv6: false

  # UNIX domain socket options.
  unixDomainSocket:
    # Enable or disable listening on the UNIX domain socket.
    enabled: false
    # The path for the UNIX socket.
    pathPrefix: {{ $mongodb_root }}/tmp
    # Sets the permission for the UNIX domain socket file.
    filePermissions: 0700

  # Network compression options.
  compression:
    # Comma-separated list of compressors to use.
    # Options: "snappy", "zstd", "zlib", "disabled"
    compressors: "snappy,zstd,zlib"

  # TLS/SSL options.
  tls:
    # If true, clients are not required to provide a certificate.
    allowConnectionsWithoutCertificates: false
    # Disables validation checks for TLS certificates and allows invalid certificates.
    allowInvalidCertificates: false
    # Disables validation of hostnames in TLS certificates.
    allowInvalidHostnames: false
    # Enables or disables FIPS mode. (Enterprise Only)
    # FIPSMode: false

#----------------------------------------------------------------------
# 4. Process Management
#----------------------------------------------------------------------
processManagement:
  # Enable daemon mode that runs the process in the background.
  fork: false
  # The file location to store the process ID (PID) of the mongod process.
  pidFilePath: {{ $mongodb_root }}/tmp/mongodb.pid

  # Windows service options
  # windowsService:
  #   serviceName: "MongoDB"
  #   displayName: "MongoDB"
  #   description: "MongoDB Server"

#----------------------------------------------------------------------
# 5. Security
#----------------------------------------------------------------------
security:
  # The authentication mode for cluster authentication.
  # Options: "keyFile", "sendKeyFile", "sendX509", "x509"
  clusterAuthMode: "keyFile"

  # Enables or disables Role-Based Access Control.
  # Options: "enabled", "disabled"
  authorization: "enabled"

  # The path to the key file used for authentication.
  keyFile: /etc/mongodb/keyfile

  # Allows a mix of authenticated and non-authenticated connections for rolling upgrades.
  transitionToAuth: false

  # Enables or disables server-side JavaScript execution.
  javascriptEnabled: true

  # Redacts any message accompanying a given log event before logging. (Enterprise Only)
  # redactClientLogData: false

  # SASL options.
  sasl:
    # Registered name of the service using SASL (e.g., for Kerberos).
    serviceName: "mongodb"

  # Encryption at rest options (Enterprise Only).
  # enableEncryption: false
  # encryptionCipherMode: "AES256-CBC"

  # KMIP options (Enterprise Only).
  # kmip:
  #   port: "5696"
  #   connectRetries: 0
  #   connectTimeoutMS: 5000
  #   activateKeys: true
  #   keyStatePollingSeconds: 900
  #   useLegacyProtocol: false
  #   rotateMasterKey: false

  # LDAP options (Enterprise Only).
  # ldap:
  #   bind:
  #     useOSDefaults: false
  #     method: "simple"
  #     saslMechanisms: "DIGEST-MD5"
  #   transportSecurity: "tls"
  #   timeoutMS: 10000
  #   retryCount: 0
  #   validateLDAPServerConfig: true

#----------------------------------------------------------------------
# 6. Operation Profiling
#----------------------------------------------------------------------
operationProfiling:
  # Specifies which operations should be profiled.
  # Options: "off", "slowOp", "all"
  mode: "off"

  # The slow operation time threshold in milliseconds.
  slowOpThresholdMs: 100

  # The fraction of slow operations (0.0-1.0) that should be profiled or logged.
  slowOpSampleRate: 1.0

#----------------------------------------------------------------------
# 7. Replication
#----------------------------------------------------------------------
replication:
  # Enables support for "majority" read concern.
  enableMajorityReadConcern: true
  # The name of the replica set.
  replSetName: replicaset

#----------------------------------------------------------------------
# 8. Sharding
#----------------------------------------------------------------------
sharding:
  # If true, a shard archives documents from chunks that it migrates to other shards.
  archiveMovedChunks: false

#----------------------------------------------------------------------
# 9. Audit Log - (Enterprise Only)
#----------------------------------------------------------------------
# auditLog:
#   # Specifies the compression mode for audit log encryption.
#   compressionMode: "none"
#   # Specifies the format used for audit logs.
#   schema: "mongo"

#----------------------------------------------------------------------
# 10. setParameter
#----------------------------------------------------------------------
setParameter:
  # --- Authentication Parameters ---
  allowRolesFromX509Certificates: true
  authFailedDelayMs: 0
  awsSTSRetryCount: 2
  enableLocalhostAuthBypass: true
  KeysRotationIntervalSec: 7776000
  ldapConnectionPoolHostRefreshIntervalMillis: 60000
  ldapConnectionPoolIdleHostTimeoutSecs: 300
  ldapConnectionPoolMaximumConnectionsInProgressPerHost: 2
  ldapConnectionPoolMaximumConnectionsPerHost: 2147483647
  ldapConnectionPoolMinimumConnectionsPerHost: 1
  ldapConnectionPoolUseLatencyForHostPriority: true
  ldapForceMultiThreadMode: false
  ldapRetryCount: 0
  ldapShouldRefreshUserCacheEntries: true
  ldapUserCacheInvalidationInterval: 30
  ldapUserCacheRefreshInterval: 30
  ldapUserCacheStalenessInterval: 90
  maxValidateMemoryUsageMB: 200
  ocspEnabled: true
  pessimisticConnectivityCheckForAcceptedConnections: false
  scramIterationCount: 10000
  scramSHA256IterationCount: 15000
  tlsOCSPVerifyTimeoutSecs: 5
  tlsUseSystemCA: false
  tlsWithholdClientCertificate: false
  tlsX509ExpirationWarningThresholdDays: 30
  auditAuthorizationSuccess: false
  auditConfigPollingFrequencySecs: 300
  auditEncryptKeyWithKMIPGet: false

  # --- General Parameters ---
  allowDiskUseByDefault: true
  connPoolMaxConnsPerHost: 200
  cursorTimeoutMillis: 600000
  fassertOnLockTimeoutForStepUpDown: 15
  indexBuildMinAvailableDiskSpaceMB: 500
  indexMaxNumGeneratedKeysPerDocument: 100000
  ingressAdmissionControllerTicketPoolSize: 1000000
  maxIndexBuildMemoryUsageMegabytes: 200
  maxNumActiveUserIndexBuilds: 3
  reportOpWriteConcernCountersInServerStatus: false
  slowConnectionThresholdMillis: 100
  tcmallocEnableBackgroundThread: true
  tcmallocReleaseRate: 0.0
  tcpFastOpenClient: true
  tcpFastOpenQueueSize: 1024
  tcpFastOpenServer: true
  ttlMonitorEnabled: true
  watchdogPeriodSeconds: -1
  planCacheSize: "5%"

  # --- Logging Parameters ---
  enableDetailedConnectionHealthMetricLogLines: true
  logLevel: 0
  maxLogSizeKB: 10
  profileOperationResourceConsumptionMetrics: false
  redactEncryptedFields: true
  suppressNoTLSPeerCertificateWarning: false

  # --- Diagnostic Parameters ---
  diagnosticDataCollectionDirectorySizeMB: 250
  diagnosticDataCollectionEnabled: true
  diagnosticDataCollectionFileSizeMB: 10
  diagnosticDataCollectionPeriodMillis: 1000

  # --- Replication and Consistency Parameters ---
  allowMultipleArbiters: false
  connectTimeoutMs: 10000
  createRollbackDataFiles: true
  disableSplitHorizonIPCheck: false
  enableFlowControl: true
  enableOverrideClusterChainingSetting: false
  flowControlTargetLagSeconds: 10
  flowControlWarnThresholdSeconds: 10
  heartBeatFrequencyMs: 10000
  initialSyncMethod: "logical"
  initialSyncTransientErrorRetryPeriodSeconds: 86400
  localLogicalSessionTimeoutMinutes: 30
  localThresholdMs: 15
  logicalSessionRefreshMillis: 300000
  maxAcceptableLogicalClockDriftSecs: 31536000
  maxNumSyncSourceChangesPerHour: 3
  maxSessions: 1000000
  mirrorReads:
    samplingRate: 0.01
    maxTimeMS: 1000
  oplogBatchDelayMillis: 0
  oplogFetcherUsesExhaust: true
  oplogInitialFindMaxSeconds: 60
  periodicNoopIntervalSecs: 10
  replBatchLimitBytes: 104857600
  replicaSetMonitorProtocol: "streamable"
  replWriterMinThreadCount: 0
  replWriterThreadCount: 16
  rollbackTimeLimitSecs: 86400
  TransactionRecordMinimumLifetimeMinutes: 30
  waitForSecondaryBeforeNoopWriteMS: 10

  # --- Sharding Parameters ---
  analyzeShardKeyCharacteristicsDefaultSampleSize: 10000000
  analyzeShardKeyMonotonicityCorrelationCoefficientThreshold: 0.7
  analyzeShardKeyNumMostCommonValues: 5
  analyzeShardKeyNumRanges: 100
  autoMergerIntervalSecs: 3600
  autoMergerThrottlingMS: 15000
  balancerMigrationsThrottlingMs: 1000
  catalogCacheCollectionMaxEntries: 10000
  catalogCacheDatabaseMaxEntries: 10000
  catalogCacheIndexMaxEntries: 10000
  chunkDefragmentationThrottlingMS: 0
  disableResumableRangeDeleter: false
  enableFinerGrainedCatalogCacheRefresh: true
  enableShardedIndexConsistencyCheck: true
  findChunksOnConfigTimeoutMS: 900000
  maxCatchUpPercentageBeforeBlockingWrites: 10
  metadataRefreshInTransactionMaxWaitBehindCritSecMS: 500
  migrateCloneInsertionBatchDelayMS: 0
  migrateCloneInsertionBatchSize: 0
  orphanCleanupDelaySecs: 900
  persistedChunkCacheUpdateMaxBatchSize: 1000
  queryAnalysisSampleExpirationSecs: 604800
  queryAnalysisSamplerConfigurationRefreshSecs: 10
  queryAnalysisWriterIntervalSecs: 90
  queryAnalysisWriterMaxBatchSize: 100000
  queryAnalysisWriterMaxMemoryUsageBytes: 104857600
  rangeDeleterBatchDelayMS: 20
  rangeDeleterBatchSize: 2147483647
  routingTableCacheChunkBucketSize: 500
  shardedIndexConsistencyCheckIntervalMS: 600000
  ShardingTaskExecutorPoolHostTimeoutMS: 300000
  ShardingTaskExecutorPoolMaxConnecting: 2
  ShardingTaskExecutorPoolMaxSize: 18446744073709551615
  ShardingTaskExecutorPoolMaxSizeForConfigServers: -1
  ShardingTaskExecutorPoolMinSize: 1
  ShardingTaskExecutorPoolMinSizeForConfigServers: -1
  ShardingTaskExecutorPoolRefreshRequirementMS: 60000
  ShardingTaskExecutorPoolRefreshTimeoutMS: 20000
  ShardingTaskExecutorPoolReplicaSetMatching: "automatic"
  shutdownTimeoutMillisForSignaledShutdown: 15000
  skipShardingConfigurationChecks: false

  # --- Storage Parameters ---
  honorSystemUmask: false
  minSnapshotHistoryWindowInSeconds: 300
  syncdelay: 60
  temporarilyUnavailableBackoffBaseMs: 1000
  temporarilyUnavailableMaxRetries: 10
  upsertMaxRetryAttemptsOnDuplicateKeyError: 100
  wiredTigerFileHandleCloseIdleTime: 600

  # --- Transaction Parameters ---
  AbortExpiredTransactionsSessionCheckoutTimeout: 100
  coordinateCommitReturnImmediatelyAfterPersistingDecision: false
  internalSessionsReapThreshold: 1000
  maxTransactionLockRequestTimeoutMillis: 5
  transactionLifetimeLimitSeconds: 60
  transactionTooLargeForCacheThreshold: 0.75
