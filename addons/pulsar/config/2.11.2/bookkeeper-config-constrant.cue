// Copyright (C) 2022-2023 ApeCloud Co., Ltd
//
// This file is part of KubeBlocks project
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// build from https://raw.githubusercontent.com/apache/pulsar/v2.11.2/conf/bookkeeper.conf

#PulsarBookkeeperParameter: {

	// Used to specify additional bind addresses for the broker. The value must format as <listener_name>:<scheme>://<host>:<port>, multiple bind addresses should be separated with commas. Associates each bind address with an advertised listener and protocol handler. Note that the brokerServicePort, brokerServicePortTls, webServicePort, and webServicePortTls properties define additional bindings.
	// bindAddresses: string

	// Enable or disable the proxy protocol.
	// haProxyProtocolEnabled: bool

	// Number of threads to use for Netty Acceptor. Default is set to `1`
	// numAcceptorThreads: int



  //// Bookie settings

  //// Server parameters

  // Port that bookie server listen on
  // bookiePort: 3181

  // Directories BookKeeper outputs its write ahead log.
  // Could define multi directories to store write head logs, separated by ','.
  // For example:
  //   journalDirectories: /tmp/bk-journal1,/tmp/bk-journal2
  // If journalDirectories is set, bookies will skip journalDirectory and use
  // this setting directory.
  // journalDirectories: /tmp/bk-journal

  // Directory Bookkeeper outputs its write ahead log
  // @deprecated since 4.5.0. journalDirectories is preferred over journalDirectory.
  journalDirectory: string

  // Configure the bookie to allow/disallow multiple ledger/index/journal directories
  // in the same filesystem disk partition
  // allowMultipleDirsUnderSameDiskPartition: false

  // Minimum safe Usable size to be available in index directory for bookie to create
  // Index File while replaying journal at the time of bookie Start in Readonly Mode (in bytes)
  minUsableSizeForIndexFileCreation: int

  // Set the network interface that the bookie should listen on.
  // If not set, the bookie will listen on all interfaces.
  // listeningInterface: eth0

  // Configure a specific hostname or IP address that the bookie should use to advertise itself to
  // clients. If not set, bookie will advertised its own IP address or hostname, depending on the
  // listeningInterface and useHostNameAsBookieID settings.
  advertisedAddress?: string

  // Whether the bookie allowed to use a loopback interface as its primary
  // interface(i.e. the interface it uses to establish its identity)?
  // By default, loopback interfaces are not allowed as the primary
  // interface.
  // Using a loopback interface as the primary interface usually indicates
  // a configuration error. For example, its fairly common in some VPS setups
  // to not configure a hostname, or to have the hostname resolve to
  // 127.0.0.1. If this is the case, then all bookies in the cluster will
  // establish their identities as 127.0.0.1:3181, and only one will be able
  // to join the cluster. For VPSs configured like this, you should explicitly
  // set the listening interface.
  allowLoopback: bool

  // Interval to watch whether bookie is dead or not, in milliseconds
  bookieDeathWatchInterval: int

  // When entryLogPerLedgerEnabled is enabled, checkpoint doesn't happens
  // when a new active entrylog is created / previous one is rolled over.
  // Instead SyncThread checkpoints periodically with 'flushInterval' delay
  // (in milliseconds) in between executions. Checkpoint flushes both ledger
  // entryLogs and ledger index pages to disk.
  // Flushing entrylog and index files will introduce much random disk I/O.
  // If separating journal dir and ledger dirs each on different devices,
  // flushing would not affect performance. But if putting journal dir
  // and ledger dirs on same device, performance degrade significantly
  // on too frequent flushing. You can consider increment flush interval
  // to get better performance, but you need to pay more time on bookie
  // server restart after failure.
  // This config is used only when entryLogPerLedgerEnabled is enabled.
  flushInterval: int

  // Allow the expansion of bookie storage capacity. Newly added ledger
  // and index dirs must be empty.
  // allowStorageExpansion: false

  // Whether the bookie should use its hostname to register with the
  // co-ordination service(eg: Zookeeper service).
  // When false, bookie will use its ip address for the registration.
  // Defaults to false.
  useHostNameAsBookieID: bool

  // If you want to custom bookie ID or use a dynamic network address for the bookie,
  // you can set this option.
  // Bookie advertises itself using bookieId rather than
  // BookieSocketAddress (hostname:port or IP:port).
  // bookieId is a non empty string that can contain ASCII digits and letters ([a-zA-Z9-0]),
  // colons, dashes, and dots.
  // For more information about bookieId, see http://bookkeeper.apache.org/bps/BP-41-bookieid/.
  // bookieId:

  // Whether the bookie is allowed to use an ephemeral port (port 0) as its
  // server port. By default, an ephemeral port is not allowed.
  // Using an ephemeral port as the service port usually indicates a configuration
  // error. However, in unit tests, using an ephemeral port will address port
  // conflict problems and allow running tests in parallel.
  allowEphemeralPorts?: bool

  // Whether allow the bookie to listen for BookKeeper clients executed on the local JVM.
  enableLocalTransport?: bool

  // Whether allow the bookie to disable bind on network interfaces,
  // this bookie will be available only to BookKeeper clients executed on the local JVM.
  disableServerSocketBind?: bool

  // The number of bytes we should use as chunk allocation for
  // org.apache.bookkeeper.bookie.SkipListArena
  skipListArenaChunkSize?: int

  // The max size we should allocate from the skiplist arena. Allocations
  // larger than this should be allocated directly by the VM to avoid fragmentation.
  skipListArenaMaxAllocSize?: int

  // The bookie authentication provider factory class name.
  // If this is null, no authentication will take place.
  bookieAuthProviderFactoryClass?: string

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Garbage collection settings
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // How long the interval to trigger next garbage collection, in milliseconds
  // Since garbage collection is running in background, too frequent gc
  // will heart performance. It is better to give a higher number of gc
  // interval if there is enough disk capacity.
  gcWaitTime: int

  // How long the interval to trigger next garbage collection of overreplicated
  // ledgers, in milliseconds [Default: 1 day]. This should not be run very frequently
  // since we read the metadata for all the ledgers on the bookie from zk
  gcOverreplicatedLedgerWaitTime: int

  // Number of threads that should handle write requests. if zero, the writes would
  // be handled by netty threads directly.
  numAddWorkerThreads: int

  // Number of threads that should handle read requests. if zero, the reads would
  // be handled by netty threads directly.
  numReadWorkerThreads: int

  // Number of threads that should be used for high priority requests
  // (i.e. recovery reads and adds, and fencing).
  numHighPriorityWorkerThreads: int

  // If read workers threads are enabled, limit the number of pending requests, to
  // avoid the executor queue to grow indefinitely
  maxPendingReadRequestsPerThread: int

  // If add workers threads are enabled, limit the number of pending requests, to
  // avoid the executor queue to grow indefinitely
  maxPendingAddRequestsPerThread: int

  // Use auto-throttling of the read-worker threads. This is done
  // to ensure the bookie is not using unlimited amount of memory
  // to respond to read-requests.
  readWorkerThreadsThrottlingEnabled: bool

  // Option to enable busy-wait settings. Default is false.
  // WARNING: This option will enable spin-waiting on executors and IO threads in order to reduce latency during
  // context switches. The spinning will consume 100% CPU even when bookie is not doing any work. It is recommended to
  // reduce the number of threads in the main workers pool and Netty event loop to only have few CPU cores busy.
  enableBusyWait: bool

  // Whether force compaction is allowed when the disk is full or almost full.
  // Forcing GC may get some space back, but may also fill up disk space more quickly.
  // This is because new log files are created before GC, while old garbage
  // log files are deleted after GC.
  isForceGCAllowWhenNoSpace?: bool

  // True if the bookie should double check readMetadata prior to gc
  verifyMetadataOnGC?: bool

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// TLS settings
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // TLS Provider (JDK or OpenSSL).
  tlsProvider?: string & "JDK" | "OpenSSL"

  // The path to the class that provides security.
  tlsProviderFactoryClass?: string

  // Type of security used by server.
  tlsClientAuthentication?: bool

  // Bookie Keystore type.
  tlsKeyStoreType?: string

  // Bookie Keystore location (path).
  tlsKeyStore?: string

  // Bookie Keystore password path, if the keystore is protected by a password.
  tlsKeyStorePasswordPath?: string

  // Bookie Truststore type.
  tlsTrustStoreType?: string

  // Bookie Truststore location (path).
  tlsTrustStore?: string

  // Bookie Truststore password path, if the trust store is protected by a password.
  tlsTrustStorePasswordPath?: string

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Long poll request parameter settings
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // The number of threads that should handle long poll requests.
  numLongPollWorkerThreads?: int

  // The tick duration in milliseconds for long poll requests.
  requestTimerTickDurationMs?: int

  // The number of ticks per wheel for the long poll request timer.
  requestTimerNumTicks?: int

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// AutoRecovery settings
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // The interval between auditor bookie checks.
  // The auditor bookie check, checks ledger metadata to see which bookies should
  // contain entries for each ledger. If a bookie which should contain entries is
  // unavailable, then the ledger containing that entry is marked for recovery.
  // Setting this to 0 disabled the periodic check. Bookie checks will still
  // run when a bookie fails.
  // The interval is specified in seconds.
  auditorPeriodicBookieCheckInterval?: int

  // The number of entries that a replication will rereplicate in parallel.
  rereplicationEntryBatchSize?: int

  // Auto-replication
  // The grace period, in milliseconds, that the replication worker waits before fencing and
  // replicating a ledger fragment that's still being written to upon bookie failure.
  openLedgerRereplicationGracePeriod?: int

  // Whether the bookie itself can start auto-recovery service also or not
  autoRecoveryDaemonEnabled?: bool

  // How long to wait, in seconds, before starting auto recovery of a lost bookie
  lostBookieRecoveryDelay?: int

  // Use older Bookkeeper wire protocol (Before Version 3) for AutoRecovery. Default is false
  useV2WireProtocol?: bool

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Placement settings
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // the following settings take effects when `autoRecoveryDaemonEnabled` is true.

  // The ensemble placement policy used for re-replicating entries.
  //
  // Options:
  //   - org.apache.bookkeeper.client.RackawareEnsemblePlacementPolicy
  //   - org.apache.bookkeeper.client.RegionAwareEnsemblePlacementPolicy
  //
  // Default value:
  //   org.apache.bookkeeper.client.RackawareEnsemblePlacementPolicy
  //
  // ensemblePlacementPolicy: org.apache.bookkeeper.client.RackawareEnsemblePlacementPolicy

  // The DNS resolver class used for resolving the network location of each bookie. All bookkeeper clients
  // should be configured with the same value to ensure that each bookkeeper client builds
  // the same network topology in order to then place ensembles consistently. The setting is used
  // when using either RackawareEnsemblePlacementPolicy and RegionAwareEnsemblePlacementPolicy.
  // The setting in this file is used to configure the bookkeeper client used in the bookkeeper, which
  // is used by the autorecovery process.
  // Some available options:
  //   - org.apache.pulsar.zookeeper.ZkBookieRackAffinityMapping (Pulsar default)
  //   - org.apache.bookkeeper.net.ScriptBasedMapping (Bookkeeper default)
  reppDnsResolverClass: string

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Netty server settings
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // This settings is used to enabled/disabled Nagle's algorithm, which is a means of
  // improving the efficiency of TCP/IP networks by reducing the number of packets
  // that need to be sent over the network.
  // If you are sending many small messages, such that more than one can fit in
  // a single IP packet, setting server.tcpnodelay to false to enable Nagle algorithm
  // can provide better performance.
  // Default value is true.
  serverTcpNoDelay: bool

  // This setting is used to send keep-alive messages on connection-oriented sockets.
  serverSockKeepalive?: bool

  // The socket linger timeout on close.
  // When enabled, a close or shutdown will not return until all queued messages for
  // the socket have been successfully sent or the linger timeout has been reached.
  // Otherwise, the call returns immediately and the closing is done in the background.
  serverTcpLinger?: int

  // The Recv ByteBuf allocator initial buf size.
  byteBufAllocatorSizeInitial?: int

  // The Recv ByteBuf allocator min buf size.
  byteBufAllocatorSizeMin?: int

  // The Recv ByteBuf allocator max buf size.
  byteBufAllocatorSizeMax?: int

  // The maximum netty frame size in bytes. Any message received larger than this will be rejected. The default value is 5MB.
  nettyMaxFrameSizeBytes: int

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Journal settings
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // The journal format version to write.
  // Available formats are 1-6:
  // 1: no header
  // 2: a header section was added
  // 3: ledger key was introduced
  // 4: fencing key was introduced
  // 5: expanding header to 512 and padding writes to align sector size configured by `journalAlignmentSize`
  // 6: persisting explicitLac is introduced
  // By default, it is `6`.
  // If you'd like to disable persisting ExplicitLac, you can set this config to < `6` and also
  // fileInfoFormatVersionToWrite should be set to 0. If there is mismatch then the serverconfig is considered invalid.
  // You can disable `padding-writes` by setting journal version back to `4`. This feature is available in 4.5.0
  // and onward versions.
  journalFormatVersionToWrite: int

  // Max file size of journal file, in mega bytes
  // A new journal file will be created when the old one reaches the file size limitation
  journalMaxSizeMB: int

  // Max number of old journal file to kept
  // Keep a number of old journal files would help data recovery in special case
  journalMaxBackups: int

  // How much space should we pre-allocate at a time in the journal.
  journalPreAllocSizeMB: int

  // Size of the write buffers used for the journal
  journalWriteBufferSizeKB: int

  // Should we remove pages from page cache after force write
  journalRemoveFromPageCache: bool

  // Should the data be written on journal.
  // By default, data is written on journal for durability of writes.
  // Beware: while disabling data journaling in the Bookie journal might improve the bookie write performance, it will also
  // introduce the possibility of data loss. With no journal, the write operations are passed to the storage engine
  // and then acknowledged. In case of power failure, the affected bookie might lose the unflushed data. If the ledger
  // is replicated to multiple bookies, the chances of data loss are reduced though still present.
  journalWriteData: bool

  // Should the data be fsynced on journal before acknowledgment.
  // By default, data sync is enabled to guarantee durability of writes.
  // Beware: while disabling data sync in the Bookie journal might improve the bookie write performance, it will also
  // introduce the possibility of data loss. With no sync, the journal entries are written in the OS page cache but
  // not flushed to disk. In case of power failure, the affected bookie might lose the unflushed data. If the ledger
  // is replicated to multiple bookies, the chances of data loss are reduced though still present.
  journalSyncData: bool

  // Should we group journal force writes, which optimize group commit
  // for higher throughput
  journalAdaptiveGroupWrites: bool

  // Maximum latency to impose on a journal write to achieve grouping
  journalMaxGroupWaitMSec: int

  // Maximum writes to buffer to achieve grouping
  journalBufferedWritesThreshold: int

  // The number of threads that should handle journal callbacks
  numJournalCallbackThreads: int

  // All the journal writes and commits should be aligned to given size.
  // If not, zeros will be padded to align to given size.
  // It only takes effects when journalFormatVersionToWrite is set to 5
  journalAlignmentSize: int

  // Maximum entries to buffer to impose on a journal write to achieve grouping.
  journalBufferedEntriesThreshold?: int

  // If we should flush the journal when journal queue is empty
  journalFlushWhenQueueEmpty: bool

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Ledger storage settings
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // Ledger storage implementation class
  ledgerStorageClass: string

  // Directory Bookkeeper outputs ledger snapshots
  // could define multi directories to store snapshots, separated by ','
  // For example:
  // ledgerDirectories: /tmp/bk1-data,/tmp/bk2-data
  //
  // Ideally ledger dirs and journal dir are each in a different device,
  // which reduce the contention between random i/o and sequential write.
  // It is possible to run with a single disk, but performance will be significantly lower.
  ledgerDirectories: string
  // Directories to store index files. If not specified, will use ledgerDirectories to store.
  indexDirectories: string

  // Interval at which the auditor will do a check of all ledgers in the cluster.
  // By default this runs once a week. The interval is set in seconds.
  // To disable the periodic check completely, set this to 0.
  // Note that periodic checking will put extra load on the cluster, so it should
  // not be run more frequently than once a day.
  auditorPeriodicCheckInterval: int

  // Whether sorted-ledger storage enabled (default true)
  sortedLedgerStorageEnabled?: bool

  // The skip list data size limitation (default 64MB) in EntryMemTable
  skipListSizeLimit?: int

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Ledger cache settings
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // Max number of ledger index files could be opened in bookie server
  // If number of ledger index files reaches this limitation, bookie
  // server started to swap some ledgers from memory to disk.
  // Too frequent swap will affect performance. You can tune this number
  // to gain performance according your requirements.
  openFileLimit: int

  // The fileinfo format version to write.
  //  Available formats are 0-1:
  //   0: Initial version
  //   1: persisting explicitLac is introduced
  // By default, it is `1`.
  // If you'd like to disable persisting ExplicitLac, you can set this config to 0 and
  // also journalFormatVersionToWrite should be set to < 6. If there is mismatch then the
  // serverconfig is considered invalid.
  fileInfoFormatVersionToWrite: int

  // Size of a index page in ledger cache, in bytes
  // A larger index page can improve performance writing page to disk,
  // which is efficient when you have small number of ledgers and these
  // ledgers have similar number of entries.
  // If you have large number of ledgers and each ledger has fewer entries,
  // smaller index page would improve memory usage.
  pageSize?: int

  // How many index pages provided in ledger cache
  // If number of index pages reaches this limitation, bookie server
  // starts to swap some ledgers from memory to disk. You can increment
  // this value when you found swap became more frequent. But make sure
  // pageLimit*pageSize should not more than JVM max memory limitation,
  // otherwise you would got OutOfMemoryException.
  // In general, incrementing pageLimit, using smaller index page would
  // gain better performance in lager number of ledgers with fewer entries case
  // If pageLimit is -1, bookie server will use 1/3 of JVM memory to compute
  // the limitation of number of index pages.
  pageLimit: int

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Ledger manager settings
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // Ledger Manager Class
  // What kind of ledger manager is used to manage how ledgers are stored, managed
  // and garbage collected. Try to read 'BookKeeper Internals' for detail info.
  ledgerManagerFactoryClass: string

  // @Deprecated - `ledgerManagerType` is deprecated in favor of using `ledgerManagerFactoryClass`.
  // ledgerManagerType: hierarchical

  // Root Zookeeper path to store ledger metadata
  // This parameter is used by zookeeper-based ledger manager as a root znode to
  // store all ledgers.
  zkLedgersRootPath: string

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Entry log settings
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // Max file size of entry logger, in bytes
  // A new entry log file will be created when the old one reaches the file size limitation
  logSizeLimit: int

  // Enable/Disable entry logger preallocation
  entryLogFilePreallocationEnabled: bool

  // Entry log flush interval in bytes.
  // Default is 0. 0 or less disables this feature and effectively flush
  // happens on log rotation.
  // Flushing in smaller chunks but more frequently reduces spikes in disk
  // I/O. Flushing too frequently may also affect performance negatively.
  flushEntrylogBytes: int

  // The number of bytes we should use as capacity for BufferedReadChannel. Default is 512 bytes.
  readBufferSizeBytes: int

  // The number of bytes used as capacity for the write buffer. Default is 64KB.
  writeBufferSizeBytes: int

  // Specifies if entryLog per ledger is enabled/disabled. If it is enabled, then there would be a
  // active entrylog for each ledger. It would be ideal to enable this feature if the underlying
  // storage device has multiple DiskPartitions or SSD and if in a given moment, entries of fewer
  // number of active ledgers are written to a bookie.
  entryLogPerLedgerEnabled?: bool

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Entry log compaction settings
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // Set the rate at which compaction will readd entries. The unit is adds per second.
  compactionRate: int

  // If bookie is using hostname for registration and in ledger metadata then
  // whether to use short hostname or FQDN hostname. Defaults to false.
  useShortHostName?: bool

  // Threshold of minor compaction
  // For those entry log files whose remaining size percentage reaches below
  // this threshold will be compacted in a minor compaction.
  // If it is set to less than zero, the minor compaction is disabled.
  minorCompactionThreshold: float

  // Interval to run minor compaction, in seconds
  // If it is set to less than zero, the minor compaction is disabled.
  // Note: should be greater than gcWaitTime.
  minorCompactionInterval: int

  // Set the maximum number of entries which can be compacted without flushing.
  // When compacting, the entries are written to the entrylog and the new offsets
  // are cached in memory. Once the entrylog is flushed the index is updated with
  // the new offsets. This parameter controls the number of entries added to the
  // entrylog before a flush is forced. A higher value for this parameter means
  // more memory will be used for offsets. Each offset consists of 3 longs.
  // This parameter should _not_ be modified unless you know what you're doing.
  // The default is 100,000.
  compactionMaxOutstandingRequests: int

  // Threshold of major compaction
  // For those entry log files whose remaining size percentage reaches below
  // this threshold will be compacted in a major compaction.
  // Those entry log files whose remaining size percentage is still
  // higher than the threshold will never be compacted.
  // If it is set to less than zero, the minor compaction is disabled.
  majorCompactionThreshold: float

  // Interval to run major compaction, in seconds
  // If it is set to less than zero, the major compaction is disabled.
  // Note: should be greater than gcWaitTime.
  majorCompactionInterval: int

  // Throttle compaction by bytes or by entries.
  isThrottleByBytes: bool

  // Set the rate at which compaction will readd entries. The unit is adds per second.
  compactionRateByEntries: int

  // Set the rate at which compaction will readd entries. The unit is bytes added per second.
  compactionRateByBytes: int

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Statistics
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // Whether statistics are enabled
  enableStatistics?: bool

  // Stats Provider Class (if statistics are enabled)
  statsProviderClass: string

  // Default port for Prometheus metrics exporter
  prometheusStatsHttpPort: int

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Read-only mode support
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // If all ledger directories configured are full, then support only read requests for clients.
  // If "readOnlyModeEnabled: true" then on all ledger disks full, bookie will be converted
  // to read-only mode and serve only read requests. Otherwise the bookie will be shutdown.
  // By default this will be disabled.
  readOnlyModeEnabled: bool

  // Whether the bookie is force started in read only mode or not
  forceReadOnlyBookie: bool

  // Persist the bookie status locally on the disks. So the bookies can keep their status upon restarts
  // @Since 4.6
  persistBookieStatusEnabled?: bool

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Disk utilization
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // For each ledger dir, maximum disk space which can be used.
  // Default is 0.95f. i.e. 95% of disk can be used at most after which nothing will
  // be written to that partition. If all ledger dir partitions are full, then bookie
  // will turn to readonly mode if 'readOnlyModeEnabled: true' is set, else it will
  // shutdown.
  // Valid values should be in between 0 and 1 (exclusive).
  diskUsageThreshold: float

  // The disk free space low water mark threshold.
  // Disk is considered full when usage threshold is exceeded.
  // Disk returns back to non-full state when usage is below low water mark threshold.
  // This prevents it from going back and forth between these states frequently
  // when concurrent writes and compaction are happening. This also prevent bookie from
  // switching frequently between read-only and read-writes states in the same cases.
  diskUsageWarnThreshold: float

  // Set the disk free space low water mark threshold. Disk is considered full when
  // usage threshold is exceeded. Disk returns back to non-full state when usage is
  // below low water mark threshold. This prevents it from going back and forth
  // between these states frequently when concurrent writes and compaction are
  // happening. This also prevent bookie from switching frequently between
  // read-only and read-writes states in the same cases.
  diskUsageLwmThreshold: float

  // Disk check interval in milli seconds, interval to check the ledger dirs usage.
  // Default is 10000
  diskCheckInterval: int


  //////////////////////////////////////////////////////////////////////////////////////////// Metadata Services   ////////////////////////////////////////////////////////////////////////////////////////////


  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Metadata Service settings
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // metadata service uri that bookkeeper is used for loading corresponding metadata driver and resolving its metadata service location
	// Examples:
	//  - metadataServiceUri=metadata-store:zk:my-zk-1:2181
	//  - metadataServiceUri=metadata-store:etcd:http://my-etcd:2379
  // metadataServiceUri?: string

  // @Deprecated - `ledgerManagerFactoryClass` is deprecated in favor of using `metadataServiceUri`
  // Ledger Manager Class
  // What kind of ledger manager is used to manage how ledgers are stored, managed
  // and garbage collected. Try to read 'BookKeeper Internals' for detail info.
  ledgerManagerFactoryClass?: string

  // @Deprecated - `ledgerManagerType` is deprecated in favor of using `ledgerManagerFactoryClass`.
  // ledgerManagerType: hierarchical

  // sometimes the bookkeeper server classes are shaded. the ledger manager factory classes might be relocated to be under other packages.
  // this would fail the clients using shaded factory classes since the factory classes are not matched. Users can enable this flag to
  // allow using shaded ledger manager class to connect to a bookkeeper cluster.
  allowShadedLedgerManagerFactoryClass?: bool

  // the shaded ledger manager factory prefix. this is used when `allowShadedLedgerManagerFactoryClass` is set to true.
  shadedLedgerManagerFactoryClassPrefix?: string


  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// ZooKeeper parameters
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // @Deprecated - `zkServers` is deprecated in favor of using `metadataServiceUri`
  // A list of one of more servers on which Zookeeper is running.
  // The server list can be comma separated values, for example:
  // zkServers: zk1:2181,zk2:2181,zk3:2181
  // zkServers: string

  // ZooKeeper client session timeout in milliseconds
  // Bookie server will exit if it received SESSION_EXPIRED because it
  // was partitioned off from ZooKeeper for more than the session timeout
  // JVM garbage collection, disk I/O will cause SESSION_EXPIRED.
  // Increment this value could help avoiding this issue
  zkTimeout: int

  // The Zookeeper client backoff retry start time in millis.
  zkRetryBackoffStartMs?: int

  // The Zookeeper client backoff retry max time in millis.
  zkRetryBackoffMaxMs?: int

  // Set ACLs on every node written on ZooKeeper, this way only allowed users
  // will be able to read and write BookKeeper metadata stored on ZooKeeper.
  // In order to make ACLs work you need to setup ZooKeeper JAAS authentication
  // all the bookies and Client need to share the same user, and this is usually
  // done using Kerberos authentication. See ZooKeeper documentation
  zkEnableSecurity: bool

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// Server parameters
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // The flag enables/disables starting the admin http server. Default value is 'false'.
  httpServerEnabled: bool

  // The http server port to listen on. Default value is 8080.
  // Use `8000` as the port to keep it consistent with prometheus stats provider
  httpServerPort: int

  // The http server class
  httpServerClass: string

  // Configure a list of server components to enable and load on a bookie server.
  // This provides the plugin run extra services along with a bookie server.
  //
  // extraServerComponents:


  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  //// DB Ledger storage configuration
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

  // These configs are used when the selected 'ledgerStorageClass' is
  // org.apache.bookkeeper.bookie.storage.ldb.DbLedgerStorage

  // Size of Write Cache. Memory is allocated from JVM direct memory.
  // Write cache is used to buffer entries before flushing into the entry log
  // For good performance, it should be big enough to hold a substantial amount
  // of entries in the flush interval
  //  By default it will be allocated to 1/4th of the available direct memory
  dbStorage_writeCacheMaxSizeMb?: int

  // Size of Read cache. Memory is allocated from JVM direct memory.
  // This read cache is pre-filled doing read-ahead whenever a cache miss happens
  //  By default it will be allocated to 1/4th of the available direct memory
  dbStorage_readAheadCacheMaxSizeMb?: int

  // How many entries to pre-fill in cache after a read cache miss
  dbStorage_readAheadCacheBatchSize: int

  //// RocksDB specific configurations
  //// DbLedgerStorage uses RocksDB to store the indexes from
  //// (ledgerId, entryId) -> (entryLog, offset)

  // Size of RocksDB block-cache. For best performance, this cache
  // should be big enough to hold a significant portion of the index
  // database which can reach ~2GB in some cases
  // Default is to use 10% of the direct memory size
  dbStorage_rocksDB_blockCacheSize?: int

  // Other RocksDB specific tunables
  dbStorage_rocksDB_writeBufferSizeMB: int
  dbStorage_rocksDB_sstSizeInMB: int
  dbStorage_rocksDB_blockSize: int
  dbStorage_rocksDB_bloomFilterBitsPerKey: int
  dbStorage_rocksDB_numLevels: int
  dbStorage_rocksDB_numFilesInLevel0: int
  dbStorage_rocksDB_maxSizeInLevel1MB: int

	...
}

configuration: #PulsarBookkeeperParameter & {
}
