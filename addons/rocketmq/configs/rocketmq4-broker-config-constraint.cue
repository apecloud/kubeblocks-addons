// https://rocketmq.apache.org/zh/docs/4.x/parameterConfiguration/02server
// https://github.com/apache/rocketmq/blob/rocketmq-all-4.9.6/common/src/main/java/org/apache/rocketmq/common/BrokerConfig.java
// https://github.com/apache/rocketmq/blob/rocketmq-all-4.9.6/remoting/src/main/java/org/apache/rocketmq/remoting/netty/NettyServerConfig.java
// https://github.com/apache/rocketmq/blob/rocketmq-all-4.9.6/store/src/main/java/org/apache/rocketmq/store/config/MessageStoreConfig.java
#RocketMQBrokerParameter: {
  // The ratio of accessing messages in memory
  accessMessageInMemoryMaxRatio?: int | *40

  // Whether to enable acl permission control
  aclEnable?: bool & true | false | *false

  // Thread pool size for handling console management commands
  adminBrokerThreadPoolNums?: int | *16

  // Whether to automatically create subscription groups
  autoCreateSubscriptionGroup?: bool & true | false | *true

  // Whether to automatically create topics
  autoCreateTopicEnable?: bool & true | false | *true

  // Whether to automatically delete unused stats
  autoDeleteUnusedStats?: bool & true | false | *true

  // Use MessageVersion.MESSAGE_VERSION_V2 automatically if topic length larger than Bytes.MAX_VALUE.
  // Otherwise, store use MESSAGE_VERSION_V1. Note: Client couldn't decode MESSAGE_VERSION_V2 version message.
  // Enable this config to resolve this issue. https://github.com/apache/rocketmq/issues/5568
  autoMessageVersionOnTopicLen?: bool & true | false | *true

  // ConsumeQueue extension filter bitmap size
  bitMapLengthConsumeQueueExt?: int | *112

  // Broker cluster name, set by kb cluster name
  brokerClusterName?: string

  // Whether to enable broker fast failure
  brokerFastFailureEnable?: bool & true | false | *true

  // Broker ID, 0 for master node, >0 for slave nodes
  // set by pod index
  brokerId?: int

  // Broker service address
  brokerIP1?: string

  // Broker HA IP address for slave synchronization
  brokerIP2?: string

  // Broker server name, set by kb broker comp name
  // set by pod index, 0 for master, >0 for slave
  brokerName?: string

  // Broker permission, 6 means readable and writable
  brokerPermission?: int | *6

  // Broker role: ASYNC_MASTER, SYNC_MASTER, or SLAVE
  brokerRole?: string & "ASYNC_MASTER" | "SYNC_MASTER" | "SLAVE" | *"ASYNC_MASTER"

  // Whether broker name can be used as topic
  brokerTopicEnable?: bool & true | false | *true

  // Channel not active interval
  channelNotActiveInterval?: int | *60000

  // Whether check the CRC32 of the records consumed.
  // This ensures no on-the-wire or on-disk corruption to the messages occurred.
  // This check adds some overhead,so it may be disabled in cases seeking extreme performance.
  checkCRCOnRecover?: bool & true | false | *true

  // Whether to forcibly delete expired files
  cleanFileForciblyEnable?: bool & true | false | *true

  // Schedule frequency for cleaning expired files
  cleanResourceInterval?: int | *10000

  // Client async semaphore value
  // NettySystemConfig.CLIENT_ASYNC_SEMAPHORE_VALUE
  clientAsyncSemaphoreValue?: int

  // Number of client callback executor threads
  // default equal to the number of availableProcessors
  clientCallbackExecutorThreads?: int

  // Maximum idle time for each client channel
  clientChannelMaxIdleTimeSeconds?: int

  // Whether client needs to wait when closing socket
  clientCloseSocketIfTimeout?: bool

  // Initial queue size for client management thread pool
  clientManagerThreadPoolQueueCapacity?: int | *1000000

  // Number of threads for client management
  clientManageThreadPoolNums?: int | *32

  // Client oneway semaphore value
  // NettySystemConfig.CLIENT_ONEWAY_SEMAPHORE_VALUE
  clientOnewaySemaphoreValue?: int

  // Whether to enable client pooled byte buffer
  clientPooledByteBufAllocatorEnable?: bool & true | false | *false

  // Client socket receive buffer size
  // NettySystemConfig.socketRcvbufSize
  clientSocketRcvBufSize?: int

  // Client socket send buffer size
  // NettySystemConfig.socketSndbufSize
  clientSocketSndBufSize?: int

  // Number of worker threads
  // NettySystemConfig.clientWorkerSize
  clientWorkerThreads?: int

  // Whether cluster name can be used in topic
  clusterTopicEnable?: bool & true | false | *true

  // Whether to enable commerical
  commercialEnable?: bool & true | false | *true

  commercialBaseCount?: int | *1

  commercialBigCount?: int | *1

  commercialTimerCount?: int | *1

  commercialTransCount?: int | *1

  // Minimum number of dirty pages for commit
  // How many pages are to be committed when commit data to file
  commitCommitLogLeastPages?: int | *4

  // Maximum interval between two commits
  commitCommitLogThoroughInterval?: int | *200

  // Commit log commit frequency
  // Only used if TransientStorePool enabled
  // flush data to FileChannel
  commitIntervalCommitLog?: int | *200

  // Whether to enable message compression
  compressedRegister?: bool & true | false | *false

  // Connection timeout in milliseconds
  connectTimeoutMillis?: int | *3000

  // Consumer fallbehind threshold
  consumerFallbehindThreshold?: int | *17179869184

  // Consumer management thread pool queue capacity
  consumerManagerThreadPoolQueueCapacity?: int | *1000000

  // Number of threads for consumer management
  consumerManageThreadPoolNums?: int | *32

  // Whether to enable PutMessage Lock information printing
  debugLockEnable?: bool & true | false | *false

  // Default maximum number of query results
  defaultQueryMaxNum?: int | *32

  // Number of queues created for a topic on one broker
  defaultTopicQueueNums?: int | *8

  // Interval for deleting commit log files
  deleteCommitLogFilesInterval?: int | *100

  // Interval for deleting consume queue files
  deleteConsumeQueueFilesInterval?: int | *100

  // When to delete,default is at 4 am
  deleteWhen?: string | *"04"

  // Maximum survival time of rejected MappedFile
  destroyMapedFileIntervalForcibly?: int | *120000

  // Whether to disable consumption for slow consumers
  disableConsumeIfConsumerReadSlowly?: bool & true | false | *false

  // Whether to record disk usage statistics
  diskFallRecorded?: bool & true | false | *true

  // Maximum disk usage ratio
  diskMaxUsedSpaceRatio?: int | *75

  // Whether to allow duplicate replication
  duplicationEnable?: bool & true | false | *false

  // Switch of filter bit map calculation.
	// If switch on:
	// 1. Calculate filter bit map when construct queue.
	// 2. Filter bit map will be saved to consume queue extend file if allowed.
  enableCalcFilterBitMap?: bool & true | false | *false

  // Whether to enable ConsumeQueue extension
  enableConsumeQueueExt?: bool & true | false | *false

  // Whether to enable detail stat
  enableDetailStat?: bool & true | false | *true

	// Whether to enable dleger commit log
  enableDLegerCommitLog?: bool & true | false | *false

	// Whether to enable lmq
  enableLmq?: bool & true | false | *false

  // Whether to enable multi dispatch
  enableMultiDispatch?: bool & true | false | *false

  // Whether to enable property filtering
  enablePropertyFilter?: bool & true | false | *false

  // Whether to enable schedule async deliver
  enableScheduleAsyncDeliver?: bool & true | false | *false

  // Whether to enable schedule message stats
  enableScheduleMessageStats?: bool & true | false | *true

  // Transaction processing thread pool queue capacity
  endTransactionPoolQueueCapacity?: int |*100000

  // Number of transaction processing threads
  // Math.max(8 + Runtime.getRuntime().availableProcessors() * 2, sendMessageThreadPoolNums * 4);
  endTransactionThreadPoolNums?: int

  // Expected number of consumers using filter
  expectConsumerNumUseFilter?: int | *32

  // Whether to enable fast failure when no buffer in store pool
  fastFailIfNoBufferInStorePool?: bool & true | false | *false

  // Whether to fetch namesrv address from server
  fetchNamesrvAddrByAddressServer?: bool & true | false | *false

  // The number of hours to keep a log file before deleting it (in hours)
  fileReservedTime?: string | *"72"

  // how long to clean filter data after dead.Default: 24h
  filterDataCleanTimeSpan?: int | *86400000

  // Number of filter servers
  filterServerNums?: int | *0

  // Whether filter supports retry
  filterSupportRetry?: bool & true | false | *false

  // How many pages are to be flushed when flush CommitLog
  flushCommitLogLeastPages?: int | *4

  flushCommitLogThoroughInterval?: int | *10000

  // Whether to use timed flush for commit log
  flushCommitLogTimed?: bool & true | false | *true

  // Minimum number of dirty pages for flushing consume queue
  flushConsumeQueueLeastPages?: int | *2

  // Maximum interval between two consume queue flushes
  flushConsumeQueueThoroughInterval?: int | *60000

  // Interval for flushing consumer offset history
  flushConsumerOffsetHistoryInterval?: int | *60000

  // Interval for flushing consumer offset
  flushConsumerOffsetInterval?: int | *5000

  // Interval for flushing delay offset
  flushDelayOffsetInterval?: int | *10000

  // Disk flush type
  flushDiskType?: string & "ASYNC_FLUSH" | "SYNC_FLUSH" | *"ASYNC_FLUSH"

  // CommitLog flush interval
  // flush data to disk
  flushIntervalCommitLog?: int | *500

  // Consume queue flush interval
  flushIntervalConsumeQueue?: int | *1000

  // Flush page size when the disk in warming state
  flushLeastPagesWhenWarmMapedFile?: int | *4096

	// Whether to force register
  forceRegister?: bool & true | false | *true

	haHousekeepingInterval?: int | *20000

	haListenPort?: int

	haSendHeartbeatInterval?: int | *5000

	haSlaveFallbehindMax?: int | *268435346

	haTransferBatchSize?: int | *32768

	// Math.min(32, Runtime.getRuntime().availableProcessors())
  heartbeatThreadPoolNums?: int

  heartbeatThreadPoolQueueCapacity?: int | *50000

  highSpeedMode?: bool & true | false | *false

	// Whether to distinguish log paths when multiple brokers are deployed on the same machine
  isolateLogEnable?: bool & true | false | *false

  isEnableBatchPush?: bool & true | false | *false

  listenPort?: int

	longPollingEnable?: bool & true | false | *true

	// CommitLog file size,default is 1G
	mappedFileSizeCommitLog?: int | *1073741824

	// ConsumeQueue file size,default is 30W
	// 300000 * ConsumeQueue.CQ_STORE_UNIT_SIZE;
	mappedFileSizeConsumeQueue?: int

	// ConsumeQueue extend file size, 48M
	mappedFileSizeConsumeQueueExt?: int | *50331648

	maxDelayTime?: int | *40

	// Error rate of bloom filter, 1~100
	maxErrorRateOfBloomFilter?: int | *20

	maxHashSlotNum?: int | *5000000

	maxIndexNum?: int | *20000000

	maxLmqConsumeQueueNum?: int | *20000

	// The maximum size of message body,default is 4M,4M only for body length,not include others.
	maxMessageSize?: int | *4194304

	maxMsgsNumBatch?: int | *64

	maxTransferBytesOnMessageInDisk?: int | *65536

	maxTransferBytesOnMessageInMemory?: int | *262144

	maxTransferCountOnMessageInDisk?: int | *8

	maxTransferCountOnMessageInMemory?: int | *32

	messageDelayLevel?: string | *"1s 5s 10s 30s 1m 2m 3m 4m 5m 6m 7m 8m 9m 10m 20m 30m 1h 2h"

	messageIndexEnable?: bool & true | false | *true

	messageIndexSafe?: bool & true | false | *false

	messageStorePlugIn?: string

	msgTraceTopicName?: string | *"RMQ_SYS_TRACE_TOPIC"

	namesrvAddr?: string

	notifyConsumerIdsChangedEnable?: bool & true | false | *true

	offsetCheckInSlave?: bool & true | false | *false

	osPageCacheBusyTimeOutMills?: int | *1000

	// 16 + Runtime.getRuntime().availableProcessors() * 2
	processReplyMessageThreadPoolNums?: int

	// 16 + Runtime.getRuntime().availableProcessors() * 2
	pullMessageThreadPoolNums?: int

	pullThreadPoolQueueCapacity?: int | *100000

	// Math.min(Runtime.getRuntime().availableProcessors(), 4)
	putMessageFutureThreadPoolNums?: int

	// Flow control for ConsumeQueue
	putMsgIndexHightWater?: int | *600000

	putThreadPoolQueueCapacity?: int | *10000

	// 8 + Runtime.getRuntime().availableProcessors()
	queryMessageThreadPoolNums?: int

	queryThreadPoolQueueCapacity?: int | *20000

	redeleteHangedFileInterval?: int | *120000

	regionId?: string

	registerBrokerTimeoutMills?: int | *6000

	// This configurable item defines interval of topics registration of broker to name server.
	// Allowing values are between 10, 000 and 60, 000 milliseconds.
	registerNameServerPeriod?: int | *30000

	rejectTransactionMessage?: bool & true | false | *false

	replyThreadPoolQueueCapacity?: int | *10000

	rocketmqHome?: string

	scheduleAsyncDeliverMaxPendingLimit?: int | *2000

	scheduleAsyncDeliverMaxResendNum2Blocked?: int | *3

	// Math.min(Runtime.getRuntime().availableProcessors(), 4)
	sendMessageThreadPoolNums?: int

	sendThreadPoolQueueCapacity?: int | *10000

	serverAsyncSemaphoreValue?: int | *64

	serverCallbackExecutorThreads?: int | *0

	serverChannelMaxIdleTimeSeconds?: int | *120

	serverOnewaySemaphoreValue?: int | 256

	serverPooledByteBufAllocatorEnable?: bool & true | false | *true

	serverSelectorThreads?: int | *3

	// NettySystemConfig.socketBacklog
	serverSocketBacklog?: int

	// NettySystemConfig.socketRcvbufSize
	serverSocketRcvBufSize?: int

	// NettySystemConfig.socketSndbufSize
	serverSocketSndBufSize?: int

	serverWorkerThreads?: int | *8

	shortPollingTimeMills?: int | *1000

	slaveReadEnable?: bool & true | false | *false

	slaveTimeout?: int | *3000

	startAcceptSendRequestTimeStamp?: int | *0

	storePathRootDir?: string

	storeReplyMessageEnable?: bool & true | false | *true

	syncFlushTimeout?: int | *5000

	traceOn?: bool & true | false | *true

	traceTopicEnablez?: bool & true | false | *false

	transactionCheckInterval?: int | *60000

	transactionCheckMax?: int | *15

	// The minimum time of the transactional message  to be checked firstly, one message only exceed this time interval that can be checked.
	transactionTimeOut?: int | *6000

	transferMsgByHeap?: bool & true | false | *true

	transientStorePoolEnable?: bool & true | false | *false

	transientStorePoolSize?: int | *5

	useTLS?: bool

	// make install
  // ../glibc-2.10.1/configure \ --prefix=/usr \ --with-headers=/usr/include \
  // --host=x86_64-linux-gnu \ --build=x86_64-pc-linux-gnu \ --without-gd
	useEpollNativeSelector?: bool & true | false | *false

	// introduced since 4.0.x. Determine whether to use mutex reentrantLock when putting message
	useReentrantLockWhenPutMessage?: bool & true | false | *true

	waitTimeMillsInHeartbeatQueue?: int | *31000

	waitTimeMillsInPullQueue?: int | *5000

	waitTimeMillsInSendQueue?: int | *900

	waitTimeMillsInTransactionQueue?: int | *3000

	warmMapedFileEnable?: bool & true | false | *false

	// NettySystemConfig.writeBufferHighWaterMark
	writeBufferHighWaterMark?: int

	// NettySystemConfig.writeBufferLowWaterMark
	writeBufferLowWaterMark?: int

	// other parameters
	...
}

configuration: #RocketMQBrokerParameter & {
}
