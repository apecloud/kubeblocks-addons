#TIKVParameter: {

	// Sets whether to call `abort()` to exit the process when TiKV panics. This option affects whether TiKV allows the system to generate core dump files.If the value of this configuration item is `false`, when TiKV panics, it calls `exit()` to exit the process.If the value of this configuration item is `true`, when TiKV panics, TiKV calls `abort()` to exit the process. At this time, TiKV allows the system to generate core dump files when exiting. To generate the core dump file, you also need to perform the system configuration related to core dump (for example, setting the size limit of the core dump file via `ulimit -c` command, and configure the core dump path. Different operating systems have different related configurations). To avoid the core dump files occupying too much disk space and causing insufficient TiKV disk space, it is recommended to set the core dump generation path to a disk partition different to that of TiKV data.
	"abort-on-panic": bool | *false

	// The file that stores slow logs. If this configuration item is not set, but `log.file.filename` is set, slow logs are output to the log file specified by `log.file.filename`. If neither `slow-log-file` nor `log.file.filename` are set, all logs are output to "stderr" by default. If both configuration items are set, ordinary logs are output to the log file specified by `log.file.filename`, and slow logs are output to the log file set by `slow-log-file`.
	"slow-log-file": string

	// The threshold for outputting slow logs. If the processing time is longer than this threshold, slow logs are output.
	"slow-log-threshold": string | *"1s"

	// The limit on memory usage of the TiKV instance. When the memory usage of TiKV almost reaches this threshold, internal cache will be evicted to release memory. In most cases, the TiKV instance is set to use 75% of the total available system memory, so you do not need to explicitly specify this configuration item. The rest 25% of the memory is reserved for the OS page cache. See [`storage.block-cache.capacity`](#capacity) for details. When deploying multiple TiKV nodes on a single physical machine, you still do not need to set this configuration item. In this case, the TiKV instance uses `5/3 * block-cache.capacity` of memory. The default value for different system memory capacity is as follows:system=8G    block-cache=3.6G    memory-usage-limit=6G   page-cache=2Gsystem=16G   block-cache=7.2G    memory-usage-limit=12G  page-cache=4Gsystem=32G   block-cache=14.4G   memory-usage-limit=24G  page-cache=8G
	"memory-usage-limit": string

	// The log level. Optional values: `"debug"`, `"info"`, `"warn"`, `"error"`, `"fatal"`
	"log.level": string | *"info"

	// The log format. Optional values: `"json"`, `"text"`
	"log.format": string | *"text"

	// Determines whether to enable or disable the timestamp in the log. Optional values: `true`, `false`
	"log.enable-timestamp": bool | *true

	// The log file. If this configuration item is not set, logs are output to "stderr" by default. If this configuration item is set, logs are output to the corresponding file.
	"log.file.filename": string

	// The maximum size of a single log file. When the file size is larger than the value set by this configuration item, the system automatically splits the single file into multiple files. Unit: MiB
	"log.file.max-size": float & <=4096 | *300

	// The maximum number of days that TiKV keeps log files.If the configuration item is not set, or the value of it is set to the default value `0`, TiKV does not clean log files.If the parameter is set to a value other than `0`, TiKV cleans up the expired log files after `max-days`.
	"log.file.max-days": string | *"0"

	// The maximum number of log files that TiKV keeps.If the configuration item is not set, or the value of it is set to the default value `0`, TiKV keeps all log files.If the configuration item is set to a value other than `0`, TiKV keeps at most the number of old log files specified by `max-backups`. For example, if the value is set to `7`, TiKV keeps up to 7 old log files.
	"log.file.max-backups": string | *"0"

	// The listening IP address and the listening port
	"server.addr": string | *"127.0.0.1:20160"

	// Advertise the listening address for client communication. If this configuration item is not set, the value of `addr` is used.
	"server.advertise-addr": string

	// The configuration item reports TiKV status directly through the `HTTP` address**Warning:**If this value is exposed to the public, the status information of the TiKV server might be leaked. To disable the status address, set the value to `""`.
	"server.status-addr": string | *"127.0.0.1:20180"

	// The number of worker threads for the `HTTP` API service
	"server.status-thread-pool-size": float & >=1 | *1

	// The compression algorithm for gRPC messages. Optional values: `"none"`, `"deflate"`, `"gzip"`
	"server.grpc-compression-type": string | *"none"

	// The number of gRPC worker threads. When you modify the size of the gRPC thread pool, refer to [Performance tuning for TiKV thread pools](/tune-tikv-thread-performance.md#performance-tuning-for-tikv-thread-pools).
	"server.grpc-concurrency": float & >=1 | *5

	// The maximum number of concurrent requests allowed in a gRPC stream
	"server.grpc-concurrent-stream": float & >=1 | *1024

	// Limits the memory size that can be used by gRPC. Limit the memory in case OOM is observed. Note that limit the usage can lead to potential stall
	"server.grpc-memory-pool-quota": string | *"No limit"

	// The maximum number of connections between TiKV nodes for Raft communication
	"server.grpc-raft-conn-num": float & >=1 | *1

	// Sets the maximum length of a gRPC message that can be sent. Unit: Bytes
	"server.max-grpc-send-msg-len": float & <=2.147483648e+09 | *10485760

	// The window size of the gRPC stream. Unit: KiB|MiB|GiB
	"server.grpc-stream-initial-window-size": string | *"2MiB"

	// The time interval at which that gRPC sends `keepalive` Ping messages
	"server.grpc-keepalive-time": string | *"10s"

	// Disables the timeout for gRPC streams
	"server.grpc-keepalive-timeout": string | *"3s"

	// The maximum number of snapshots sent at the same time
	"server.concurrent-send-snap-limit": float & >=1 | *32

	// The maximum number of snapshots received at the same time
	"server.concurrent-recv-snap-limit": float & >=1 | *32

	// The maximum number of recursive levels allowed when TiKV decodes the Coprocessor DAG expression
	"server.end-point-recursion-limit": float & >=1 | *1000

	// The longest duration allowed for a TiDB's push down request to TiKV for processing tasks
	"server.end-point-request-max-handle-duration": string | *"60s"

	// The maximum allowable disk bandwidth when processing snapshots. Unit: KiB|MiB|GiB
	"server.snap-io-max-bytes-per-sec": string | *"100MiB"

	// Determines whether to process requests in batches
	"server.enable-request-batch": bool | *true

	// Specifies server attributes, such as `{ zone = "us-west-1", disk = "ssd" }`.
	"server.labels": string | *"{}"

	// The working thread count of the background pool, including endpoint threads, BR threads, split-check threads, Region threads, and other threads of delay-insensitive tasks.
	// Default value: when the number of CPU cores is less than 16, the default value is 2; otherwise, the default value is 3.
	"server.background-thread-count": string | *"2"

	// The time threshold for a TiDB's push-down request to output slow log. If the processing time is longer than this threshold, the slow logs are output.
	"server.end-point-slow-log-threshold": string | *"1s"

	// Specifies the queue size of the Raft messages in TiKV. If too many messages not sent in time result in a full buffer, or messages discarded, you can specify a greater value to improve system stability.
	"server.raft-client-queue-size": string | *"16384"

	// Specifies whether to simplify the returned monitoring metrics. After you set the value to `true`, TiKV reduces the amount of data returned for each request by filtering out some metrics.
	"server.simplify-metrics": bool | *false

	// Sets the size of the connection pool for service and forwarding requests to the server. Setting it to too small a value affects the request latency and load balancing.
	"server.forward-max-connections-per-address": string | *"4"

	// The minimal working thread count of the unified read pool
	"readpool.unified.min-thread-count": string | *"1"

	// The maximum working thread count of the unified read pool or the UnifyReadPool thread pool. When you modify the size of this thread pool, refer to [Performance tuning for TiKV thread pools](/tune-tikv-thread-performance.md#performance-tuning-for-tikv-thread-pools). Value range: `[min-thread-count, MAX(4, CPU quota * 10)]`. `MAX(4, CPU quota * 10)` takes the greater value out of `4` and the `CPU quota * 10`.
	"readpool.unified.max-thread-count": string | *"MAX"

	// The stack size of the threads in the unified thread pool. Type: Integer + Unit. Unit: KiB|MiB|GiB
	"readpool.unified.stack-size": string | *"10MiB"

	// The maximum number of tasks allowed for a single thread in the unified read pool. `Server Is Busy` is returned when the value is exceeded.
	"readpool.unified.max-tasks-per-worker": float & >=2 | *2000

	// Controls whether to automatically adjust the thread pool size. When it is enabled, the read performance of TiKV is optimized by automatically adjusting the UnifyReadPool thread pool size based on the current CPU usage. The possible range of the thread pool is `[max-thread-count, MAX(4, CPU)]`. The maximum value is the same as the one of [`max-thread-count`](#max-thread-count).
	"readpool.unified.auto-adjust-pool-size": bool | *false

	// Determines whether to use the unified thread pool (configured in [`readpool.unified`](#readpoolunified)) for storage requests. If the value of this parameter is `false`, a separate thread pool is used, which is configured through the rest parameters in this section (`readpool.storage`).
	// Default value: If this section (readpool.storage) has no other configurations, the default value is true. Otherwise, for the backward compatibility, the default value is false. Change the configuration in readpool.unified as needed before enabling this option.
	"readpool.storage.use-unified-pool": string

	// The allowable number of concurrent threads that handle high-priority `read` requests. When `8` ≤ `cpu num` ≤ `16`, the default value is `cpu_num * 0.5`; when `cpu num` is smaller than `8`, the default value is `4`; when `cpu num` is greater than `16`, the default value is `8`.
	"readpool.storage.high-concurrency": string

	// The allowable number of concurrent threads that handle normal-priority `read` requests. When `8` ≤ `cpu num` ≤ `16`, the default value is `cpu_num * 0.5`; when `cpu num` is smaller than `8`, the default value is `4`; when `cpu num` is greater than `16`, the default value is `8`.
	"readpool.storage.normal-concurrency": string

	// The allowable number of concurrent threads that handle low-priority `read` requests. When `8` ≤ `cpu num` ≤ `16`, the default value is `cpu_num * 0.5`; when `cpu num` is smaller than `8`, the default value is `4`; when `cpu num` is greater than `16`, the default value is `8`.
	"readpool.storage.low-concurrency": string

	// The maximum number of tasks allowed for a single thread in a high-priority thread pool. `Server Is Busy` is returned when the value is exceeded.
	"readpool.storage.max-tasks-per-worker-high": float & >=2 | *2000

	// The maximum number of tasks allowed for a single thread in a normal-priority thread pool. `Server Is Busy` is returned when the value is exceeded.
	"readpool.storage.max-tasks-per-worker-normal": float & >=2 | *2000

	// The maximum number of tasks allowed for a single thread in a low-priority thread pool. `Server Is Busy` is returned when the value is exceeded.
	"readpool.storage.max-tasks-per-worker-low": float & >=2 | *2000

	// The stack size of threads in the Storage read thread pool. Type: Integer + Unit. Unit: KiB|MiB|GiB
	"readpool.storage.stack-size": string | *"10MiB"

	// Determines whether to use the unified thread pool (configured in [`readpool.unified`](#readpoolunified)) for coprocessor requests. If the value of this parameter is `false`, a separate thread pool is used, which is configured through the rest parameters in this section (`readpool.coprocessor`).
	// Default value: If none of the parameters in this section (readpool.coprocessor) are set, the default value is true. Otherwise, the default value is false for the backward compatibility. Adjust the configuration items in readpool.unified before enabling this parameter.
	"readpool.coprocessor.use-unified-pool": bool

	// The allowable number of concurrent threads that handle high-priority Coprocessor requests, such as checkpoints
	"readpool.coprocessor.high-concurrency": string | *"CPU * 0.8"

	// The allowable number of concurrent threads that handle normal-priority Coprocessor requests
	"readpool.coprocessor.normal-concurrency": string | *"CPU * 0.8"

	// The allowable number of concurrent threads that handle low-priority Coprocessor requests, such as table scan
	"readpool.coprocessor.low-concurrency": string | *"CPU * 0.8"

	// The number of tasks allowed for a single thread in a high-priority thread pool. When this number is exceeded, `Server Is Busy` is returned.
	"readpool.coprocessor.max-tasks-per-worker-high": float & >=2 | *2000

	// The number of tasks allowed for a single thread in a normal-priority thread pool. When this number is exceeded, `Server Is Busy` is returned.
	"readpool.coprocessor.max-tasks-per-worker-normal": float & >=2 | *2000

	// The number of tasks allowed for a single thread in a low-priority thread pool. When this number is exceeded, `Server Is Busy` is returned.
	"readpool.coprocessor.max-tasks-per-worker-low": float & >=2 | *2000

	// The stack size of the thread in the Coprocessor thread pool. Type: Integer + Unit. Unit: KiB|MiB|GiB
	"readpool.coprocessor.stack-size": string | *"10MiB"

	// The storage path of the RocksDB directory
	"storage.data-dir": string | *"./"

	// Specifies the engine type. This configuration can only be specified when creating a new cluster and cannot be modifies once being specified. Value options:`"raft-kv"`: The default engine type in versions earlier than TiDB v6.6.0.`"partitioned-raft-kv"`: The new storage engine type introduced in TiDB v6.6.0.
	"storage.engine": string | *"raft-kv"

	// A built-in memory lock mechanism to prevent simultaneous operations on a key. Each key has a hash in a different slot.
	"storage.scheduler-concurrency": float & >=1 | *524288

	// The number of threads in the Scheduler thread pool. Scheduler threads are mainly used for checking transaction consistency before data writing. If the number of CPU cores is greater than or equal to `16`, the default value is `8`; otherwise, the default value is `4`. When you modify the size of the Scheduler thread pool, refer to [Performance tuning for TiKV thread pools](/tune-tikv-thread-performance.md#performance-tuning-for-tikv-thread-pools). Value range: `[1, MAX(4, CPU)]`. In `MAX(4, CPU)`, `CPU` means the number of your CPU cores. `MAX(4, CPU)` takes the greater value out of `4` and the `CPU`.
	"storage.scheduler-worker-pool-size": string | *"4"

	// The maximum size of the write queue. A `Server Is Busy` error is returned for a new write to TiKV when this value is exceeded. Unit: MiB|GiB
	"storage.scheduler-pending-write-threshold": string | *"100MiB"

	// Determines whether Async Commit transactions respond to the TiKV client before applying prewrite requests. After enabling this configuration item, latency can be easily reduced when the apply duration is high, or the delay jitter can be reduced when the apply duration is not stable.
	"storage.enable-async-apply-prewrite": bool | *false

	// When TiKV is started, some space is reserved on the disk as disk protection. When the remaining disk space is less than the reserved space, TiKV restricts some write operations. The reserved space is divided into two parts: 80% of the reserved space is used as the extra disk space required for operations when the disk space is insufficient, and the other 20% is used to store the temporary file. In the process of reclaiming space, if the storage is exhausted by using too much extra disk space, this temporary file serves as the last protection for restoring services. The name of the temporary file is `space_placeholder_file`, located in the `storage.data-dir` directory. When TiKV goes offline because its disk space ran out, if you restart TiKV, the temporary file is automatically deleted and TiKV tries to reclaim the space. When the remaining space is insufficient, TiKV does not create the temporary file. The effectiveness of the protection is related to the size of the reserved space. The size of the reserved space is the larger value between 5% of the disk capacity and this configuration value. When the value of this configuration item is `"0MiB"`, TiKV disables this disk protection feature. Unit: MiB|GiB
	"storage.reserve-space": string | *"5GiB"

	// Set `enable-ttl` to `true` or `false` **ONLY WHEN** deploying a new TiKV cluster. **DO NOT** modify the value of this configuration item in an existing TiKV cluster. TiKV clusters with different `enable-ttl` values use different data formats. Therefore, if you modify the value of this item in an existing TiKV cluster, the cluster will store data in different formats, which causes the "can't enable TTL on a non-ttl" error when you restart the TiKV cluster. Use `enable-ttl` **ONLY IN** a TiKV cluster. **DO NOT** use this configuration item in a cluster that has TiDB nodes (which means setting `enable-ttl` to `true` in such clusters) unless `storage.api-version = 2` is configured. Otherwise, critical issues such as data corruption and the upgrade failure of TiDB clusters will occur.
	"storage.enable-ttl": string

	// The interval of checking data to reclaim physical spaces. If data reaches its TTL, TiKV forcibly reclaims its physical space during the check.
	"storage.ttl-check-poll-interval": string | *"12h"

	// The maximum allowable time for TiKV to recover after RocksDB detects a recoverable background error. If some background SST files are damaged, RocksDB will report to PD via heartbeat after locating the Peer to which the damaged SST files belong. PD then performs scheduling operations to remove this Peer. Finally, the damaged SST files are deleted directly, and the TiKV background will work as normal again. The damaged SST files still exist before the recovery finishes. During such a period, RocksDB can continue writing data, but an error will be reported when the damaged part of the data is read. If the recovery fails to finish within this time window, TiKV will panic.
	"storage.background-error-recovery-window": string | *"1h"

	// The storage format and interface version used by TiKV when TiKV serves as the RawKV store. Value options:`1`: Uses API V1, does not encode the data passed from the client, and stores data as it is. In versions earlier than v6.1.0, TiKV uses API V1 by default.`2`: Uses API V2:The data is stored in the [Multi-Version Concurrency Control (MVCC)](/glossary.md#multi-version-concurrency-control-mvcc) format, where the timestamp is obtained from PD (which is TSO) by tikv-server.Data is scoped according to different usage and API V2 supports co-existence of TiDB, Transactional KV, and RawKV applications in a single cluster.When API V2 is used, you are expected to set `storage.enable-ttl = true` at the same time. Because API V2 supports the TTL feature, you must turn on [`enable-ttl`](#enable-ttl) explicitly. Otherwise, it will be in conflict because `storage.enable-ttl` defaults to `false`.When API V2 is enabled, you need to deploy at least one tidb-server instance to reclaim obsolete data. This tidb-server instance can provide read and write services at the same time. To ensure high availability, you can deploy multiple tidb-server instances.Client support is required for API V2. For details, see the corresponding instruction of the client for the API V2.Since v6.2.0, Change Data Capture (CDC) for RawKV is supported. Refer to [RawKV CDC](https://tikv.org/docs/latest/concepts/explore-tikv-features/cdc/cdc).
	"storage.api-version": string | *"1"

	// The size of the shared block cache. Unit: KiB|MiB|GiB
	// Default value:When `storage.engine="raft-kv"`, the default value is 45% of the size of total system memory.When `storage.engine="partitioned-raft-kv"`, the default value is 30% of the size of total system memory.
	"storage.block-cache.capacity": string

	// Determines whether to enable the flow control mechanism. After it is enabled, TiKV automatically disables the write stall mechanism of KvDB and the write stall mechanism of RaftDB (excluding memtable).
	"storage.flow-control.enable": bool | *true

	// When the number of kvDB memtables reaches this threshold, the flow control mechanism starts to work. When `enable` is set to `true`, this configuration item overrides `rocksdb.(defaultcf|writecf|lockcf).max-write-buffer-number`.
	"storage.flow-control.memtables-threshold": string | *"5"

	// When the number of kvDB L0 files reaches this threshold, the flow control mechanism starts to work. When `enable` is set to `true`, this configuration item overrides `rocksdb.(defaultcf|writecf|lockcf).level0-slowdown-writes-trigger`.
	"storage.flow-control.l0-files-threshold": string | *"20"

	// When the pending compaction bytes in KvDB reach this threshold, the flow control mechanism starts to reject some write requests and reports the `ServerIsBusy` error. When `enable` is set to `true`, this configuration item overrides `rocksdb.(defaultcf|writecf|lockcf).soft-pending-compaction-bytes-limit`.
	"storage.flow-control.soft-pending-compaction-bytes-limit": string | *"192GiB"

	// When the pending compaction bytes in KvDB reach this threshold, the flow control mechanism rejects all write requests and reports the `ServerIsBusy` error. When `enable` is set to `true`, this configuration item overrides `rocksdb.(defaultcf|writecf|lockcf).hard-pending-compaction-bytes-limit`.
	"storage.flow-control.hard-pending-compaction-bytes-limit": string | *"1024GiB"

	// Limits the maximum I/O bytes that a server can write to or read from the disk (determined by the `mode` configuration item below) in one second. When this limit is reached, TiKV prefers throttling background operations over foreground ones. The value of this configuration item should be set to the disk's optimal I/O bandwidth, for example, the maximum I/O bandwidth specified by your cloud disk vendor. When this configuration value is set to zero, disk I/O operations are not limited.
	"storage.io-rate-limit.max-bytes-per-sec": string | *"0MiB"

	// Determines which types of I/O operations are counted and restrained below the `max-bytes-per-sec` threshold. Currently, only the write-only mode is supported. Value options: `"read-only"`, `"write-only"`, and `"all-io"`
	"storage.io-rate-limit.mode": string | *"write-only"

	// Controls whether the PD client in TiKV forwards requests to the leader via the followers in the case of possible network isolation. If the environment might have isolated network, enabling this parameter can reduce the window of service unavailability. If you cannot accurately determine whether isolation, network interruption, or downtime has occurred, using this mechanism has the risk of misjudgment and causes reduced availability and performance. If network failure has never occurred, it is not recommended to enable this parameter.
	"pd.enable-forwarding": bool | *false

	// The interval for retrying the PD connection.
	"pd.retry-interval": string | *"300ms"

	// Specified the frequency at which the PD client skips reporting errors when the client observes errors. For example, when the value is `5`, after the PD client observes errors, the client skips reporting errors every 4 times and reports errors every 5th time. To disable this feature, set the value to `1`.
	"pd.retry-log-every": string | *"10"

	// The maximum number of times to retry to initialize PD connection. To disable the retry, set its value to `0`. To release the limit on the number of retries, set the value to `-1`.
	"pd.retry-max-count": string | *"-1"

	// Enables or disables `prevote`. Enabling this feature helps reduce jitter on the system after recovery from network partition.
	"raftstore.prevote": bool | *true

	// The storage capacity, which is the maximum size allowed to store data. If `capacity` is left unspecified, the capacity of the current disk prevails. To deploy multiple TiKV instances on the same physical disk, add this parameter to the TiKV configuration. For details, see [Key parameters of the hybrid deployment](/hybrid-deployment-topology.md#key-parameters). Unit: KiB|MiB|GiB
	"raftstore.capacity": string | *"0"

	// The path to the Raft library, which is `storage.data-dir/raft` by default
	"raftstore.raftdb-path": string

	// The time interval at which the Raft state machine ticks
	"raftstore.raft-base-tick-interval": string | *"1s"

	// The number of passed ticks when the heartbeat is sent. This means that a heartbeat is sent at the time interval of `raft-base-tick-interval` * `raft-heartbeat-ticks`.
	"raftstore.raft-heartbeat-ticks": string | *"2"

	// The number of passed ticks when Raft election is initiated. This means that if Raft group is missing the leader, a leader election is initiated approximately after the time interval of `raft-base-tick-interval` * `raft-election-timeout-ticks`.
	"raftstore.raft-election-timeout-ticks": string | *"10"

	// The minimum number of ticks during which the Raft election is initiated. If the number is `0`, the value of `raft-election-timeout-ticks` is used. The value of this parameter must be greater than or equal to `raft-election-timeout-ticks`.
	"raftstore.raft-min-election-timeout-ticks": float & >=0 | *0

	// The maximum number of ticks during which the Raft election is initiated. If the number is `0`, the value of `raft-election-timeout-ticks` * `2` is used.
	"raftstore.raft-max-election-timeout-ticks": float & >=0 | *0

	// The soft limit on the size of a single message packet. Unit: KiB|MiB|GiB
	"raftstore.raft-max-size-per-msg": string | *"1MiB"

	// The number of Raft logs to be confirmed. If this number is exceeded, the Raft state machine slows down log sending.
	"raftstore.raft-max-inflight-msgs": float & <=16384 | *256

	// The hard limit on the maximum size of a single log. Unit: MiB|GiB
	"raftstore.raft-entry-max-size": string | *"8MiB"

	// The time interval to compact unnecessary Raft logs
	"raftstore.raft-log-compact-sync-interval": string | *"2s"

	// The time interval at which the polling task of deleting Raft logs is scheduled. `0` means that this feature is disabled.
	"raftstore.raft-log-gc-tick-interval": string | *"3s"

	// The soft limit on the maximum allowable count of residual Raft logs
	"raftstore.raft-log-gc-threshold": float & >=1 | *50

	// The hard limit on the allowable number of residual Raft logs
	// Default value: the log number that can be accommodated in the 3/4 Region size
	"raftstore.raft-log-gc-count-limit": string

	// The hard limit on the allowable size of residual Raft logs
	// Default value: 3/4 of the Region size
	"raftstore.raft-log-gc-size-limit": string

	// After the number of ticks set by this configuration item passes, even if the number of residual Raft logs does not reach the value set by `raft-log-gc-threshold`, TiKV still performs garbage collection (GC) to these logs.
	"raftstore.raft-log-reserve-max-ticks": string | *"6"

	// The interval for purging old TiKV log files to recycle disk space as soon as possible. Raft engine is a replaceable component, so the purging process is needed for some implementations.
	"raftstore.raft-engine-purge-interval": string | *"10s"

	// The maximum remaining time allowed for the log cache in memory
	"raftstore.raft-entry-cache-life-time": string | *"30s"

	// Enables or disables Hibernate Region. When this option is enabled, a Region idle for a long time is automatically set as hibernated. This reduces the extra overhead caused by heartbeat messages between the Raft leader and the followers for idle Regions. You can use `peer-stale-state-check-interval` to modify the heartbeat interval between the leader and the followers of hibernated Regions.
	"raftstore.hibernate-regions": bool | *true

	// Specifies the interval at which to check whether the Region split is needed. `0` means that this feature is disabled.
	"raftstore.split-region-check-tick-interval": string | *"10s"

	// The maximum value by which the Region data is allowed to exceed before Region split
	"raftstore.region-split-check-diff": string | *"1/16 of the Region size."

	// The time interval at which to check whether it is necessary to manually trigger RocksDB compaction. `0` means that this feature is disabled.
	"raftstore.region-compact-check-interval": string | *"5m"

	// The number of Regions checked at one time for each round of manual compaction
	// Default value:When `storage.engine="raft-kv"`, the default value is `100`.When `storage.engine="partitioned-raft-kv"`, the default value is `5`.
	"raftstore.region-compact-check-step": string

	// The number of tombstones required to trigger RocksDB compaction
	"raftstore.region-compact-min-tombstones": float & >=0 | *10000

	// The proportion of tombstone required to trigger RocksDB compaction
	"raftstore.region-compact-tombstones-percent": float & >=1 & <=100 | *30

	// The number of redundant MVCC rows required to trigger RocksDB compaction.
	"raftstore.region-compact-min-redundant-rows": float & >=0 | *50000

	// The percentage of redundant MVCC rows required to trigger RocksDB compaction.
	"raftstore.region-compact-redundant-rows-percent": float & >=1 & <=100 | *20

	// The interval at which TiKV reports bucket information to PD when `enable-region-bucket` is true.
	"raftstore.report-region-buckets-tick-interval": string | *"10s"

	// The time interval at which a Region's heartbeat to PD is triggered. `0` means that this feature is disabled.
	"raftstore.pd-heartbeat-tick-interval": string | *"1m"

	// The time interval at which a store's heartbeat to PD is triggered. `0` means that this feature is disabled.
	"raftstore.pd-store-heartbeat-tick-interval": string | *"10s"

	// The time interval at which the recycle of expired snapshot files is triggered. `0` means that this feature is disabled.
	"raftstore.snap-mgr-gc-tick-interval": string | *"1m"

	// The longest time for which a snapshot file is saved
	"raftstore.snap-gc-timeout": string | *"4h"

	// Configures the size of the `snap-generator` thread pool. To make Regions generate snapshot faster in TiKV in recovery scenarios, you need to increase the count of the `snap-generator` threads of the corresponding worker. You can use this configuration item to increase the size of the `snap-generator` thread pool.
	"raftstore.snap-generator-pool-size": float & >=1 | *2

	// The time interval at which TiKV triggers a manual compaction for the Lock Column Family
	"raftstore.lock-cf-compact-interval": string | *"10m"

	// The size out of which TiKV triggers a manual compaction for the Lock Column Family. Unit: MiB
	"raftstore.lock-cf-compact-bytes-threshold": string | *"256MiB"

	// The longest length of the Region message queue.
	"raftstore.notify-capacity": float & >=0 | *40960

	// The maximum number of messages processed per batch
	"raftstore.messages-per-tick": float & >=0 | *4096

	// The longest inactive duration allowed for a peer. A peer with timeout is marked as `down`, and PD tries to delete it later.
	"raftstore.max-peer-down-duration": string | *"10m"

	// The longest duration allowed for a peer to be in the state where a Raft group is missing the leader. If this value is exceeded, the peer verifies with PD whether the peer has been deleted.
	"raftstore.max-leader-missing-duration": string | *"2h"

	// The longest duration allowed for a peer to be in the state where a Raft group is missing the leader. If this value is exceeded, the peer is seen as abnormal and marked in metrics and logs.
	"raftstore.abnormal-leader-missing-duration": string | *"10m"

	// The time interval to trigger the check for whether a peer is in the state where a Raft group is missing the leader.
	"raftstore.peer-stale-state-check-interval": string | *"5m"

	// The maximum number of missing logs allowed for the transferee during a Raft leader transfer
	"raftstore.leader-transfer-max-log-lag": float & >=10 | *128

	// When the size of a snapshot file exceeds this configuration value, this file will be split into multiple files.
	"raftstore.max-snapshot-file-raw-size": string | *"100MiB"

	// The memory cache size required when the imported snapshot file is written into the disk. Unit: MiB
	"raftstore.snap-apply-batch-size": string | *"10MiB"

	// The time interval at which the consistency check is triggered. `0` means that this feature is disabled.
	"raftstore.consistency-check-interval": string | *"0s"

	// The longest trusted period of a Raft leader
	"raftstore.raft-store-max-leader-lease": string | *"9s"

	// Specifies the start key of the new Region when a Region is split. When this configuration item is set to `true`, the start key is the maximum split key. When this configuration item is set to `false`, the start key is the original Region's start key.
	"raftstore.right-derive-when-split": bool | *true

	// The maximum number of missing logs allowed when `merge` is performed
	"raftstore.merge-max-log-gap": string | *"10"

	// The time interval at which TiKV checks whether a Region needs merge
	"raftstore.merge-check-tick-interval": string | *"2s"

	// Determines whether to delete data from the `rocksdb delete_range` interface
	"raftstore.use-delete-range": bool | *false

	// The time interval at which the expired SST file is checked. `0` means that this feature is disabled.
	"raftstore.cleanup-import-sst-interval": string | *"10m"

	// The maximum number of read requests processed in one batch
	"raftstore.local-read-batch-size": string | *"1024"

	// The maximum number of bytes that the Apply thread can write for one FSM (Finite-state Machine) in one round of poll. This is a soft limit. Unit: KiB|MiB|GiB
	"raftstore.apply-yield-write-size": string | *"32KiB"

	// Raft state machines process data write requests in batches by the BatchSystem. This configuration item specifies the maximum number of Raft state machines that can process the requests in one batch.
	"raftstore.apply-max-batch-size": float & <=10240 | *256

	// The allowable number of threads in the pool that flushes data to the disk, which is the size of the Apply thread pool. When you modify the size of this thread pool, refer to [Performance tuning for TiKV thread pools](/tune-tikv-thread-performance.md#performance-tuning-for-tikv-thread-pools). Value ranges: `[1, CPU * 10]`. `CPU` means the number of your CPU cores.
	"raftstore.apply-pool-size": string | *"2"

	// Raft state machines process requests for flushing logs into the disk in batches by the BatchSystem. This configuration item specifies the maximum number of Raft state machines that can process the requests in one batch. If `hibernate-regions` is enabled, the default value is `256`. If `hibernate-regions` is disabled, the default value is `1024`.
	"raftstore.store-max-batch-size": string

	// The allowable number of threads in the pool that processes Raft, which is the size of the Raftstore thread pool. When you modify the size of this thread pool, refer to [Performance tuning for TiKV thread pools](/tune-tikv-thread-performance.md#performance-tuning-for-tikv-thread-pools). Value ranges: `[1, CPU * 10]`. `CPU` means the number of your CPU cores.
	"raftstore.store-pool-size": string | *"2"

	// The allowable number of threads that process Raft I/O tasks, which is the size of the StoreWriter thread pool. When you modify the size of this thread pool, refer to [Performance tuning for TiKV thread pools](/tune-tikv-thread-performance.md#performance-tuning-for-tikv-thread-pools).
	"raftstore.store-io-pool-size": float & >=0 | *0

	// The allowable number of threads that drive `future`
	"raftstore.future-poll-size": string | *"1"

	// Controls whether to enable batch processing of the requests. When it is enabled, the write performance is significantly improved.
	"raftstore.cmd-batch": bool | *true

	// At a certain interval, TiKV inspects the latency of the Raftstore component. This parameter specifies the interval of the inspection. If the latency exceeds this value, this inspection is marked as timeout. Judges whether the TiKV node is slow based on the ratio of timeout inspection.
	"raftstore.inspect-interval": string | *"100ms"

	// Determines the threshold at which Raft data is written into the disk. If the data size is larger than the value of this configuration item, the data is written to the disk. When the value of `store-io-pool-size` is `0`, this configuration item does not take effect.
	"raftstore.raft-write-size-limit": string | *"1MiB"

	// Determines the interval at which the minimum resolved timestamp is reported to the PD leader. If this value is set to `0`, it means that the reporting is disabled. Unit: second
	"raftstore.report-min-resolved-ts-interval": string | *"1s"

	// When the memory usage of TiKV exceeds 90% of the system available memory, and the memory occupied by Raft entry cache exceeds the used memory * `evict-cache-on-memory-ratio`, TiKV evicts the Raft entry cache. If this value is set to `0`, it means that this feature is disabled.
	"raftstore.evict-cache-on-memory-ratio": float & >=0 | *0.1

	// The maximum number of logs a follower is allowed to lag behind when processing read requests. If this limit is exceeded, the read request is rejected.
	"raftstore.follower-read-max-log-gap": string | *"100"

	// Controls the interval at which the Witness node periodically retrieves the replicated Raft log position from voter nodes.
	"raftstore.request-voter-replicated-index-interval": string | *"5m"

	// When TiKV uses the SlowTrend detection algorithm, this configuration item controls the sensitivity of latency detection. A higher value indicates lower sensitivity.
	"raftstore.slow-trend-unsensitive-cause": string | *"10"

	// When TiKV uses the SlowTrend detection algorithm, this configuration item controls the sensitivity of QPS detection. A higher value indicates lower sensitivity.
	"raftstore.slow-trend-unsensitive-result": string | *"0.5"

	// Determines whether to split Region by table. It is recommended for you to use the feature only in TiDB mode.
	"coprocessor.split-region-on-table": bool | *false

	// The threshold of Region split in batches. Increasing this value speeds up Region split.
	"coprocessor.batch-split-limit": float & >=1 | *10

	// The maximum size of a Region. When the value is exceeded, the Region splits into many. Unit: KiB|MiB|GiB
	// Default value: region-split-keys / 2 * 3
	"coprocessor.region-max-size": string

	// The size of the newly split Region. This value is an estimate. Unit: KiB|MiB|GiB
	"coprocessor.region-split-size": string | *"96MiB"

	// The maximum allowable number of keys in a Region. When this value is exceeded, the Region splits into many.
	// Default value: region-split-keys / 2 * 3
	"coprocessor.region-max-keys": string

	// The number of keys in the newly split Region. This value is an estimate.
	"coprocessor.region-split-keys": string | *"960000"

	// Specifies the method of data consistency check. For the consistency check of MVCC data, set the value to `"mvcc"`. For the consistency check of raw data, set the value to `"raw"`.
	"coprocessor.consistency-check-method": string | *"mvcc"

	// The path of the directory where compiled coprocessor plugins are located. Plugins in this directory are automatically loaded by TiKV. If this configuration item is not set, the coprocessor plugin is disabled.
	"coprocessor-v2.coprocessor-plugin-directory": string | *"./coprocessors"

	// Determines whether to divide a Region into smaller ranges called buckets. The bucket is used as the unit of the concurrent query to improve the scan concurrency. For more about the design of the bucket, refer to [Dynamic size Region](https://github.com/tikv/rfcs/blob/master/text/0082-dynamic-size-region.md).
	"coprocessor-v2.enable-region-bucket": bool | *false

	// The size of a bucket when `enable-region-bucket` is true.
	"coprocessor-v2.region-bucket-size": string | *"50MiB"

	// rocksdb config is currently removed due to its complexity to parse

	// The number of background threads in RocksDB. When you modify the size of the RocksDB thread pool, refer to [Performance tuning for TiKV thread pools](/tune-tikv-thread-performance.md#performance-tuning-for-tikv-thread-pools).
	"raftdb.max-background-jobs": float & >=2 | *4

	// The number of concurrent sub-compaction operations performed in RocksDB
	"raftdb.max-sub-compactions": float & >=1 | *2

	// The total number of files that RocksDB can open
	"raftdb.max-open-files": float & >=-1 | *40960

	// The maximum size of a RocksDB Manifest file. Unit: B|KiB|MiB|GiB
	"raftdb.max-manifest-file-size": string | *"20MiB"

	// If the value is `true`, the database will be created if it is missing
	"raftdb.create-if-missing": bool | *true

	// The interval at which statistics are output to the log
	"raftdb.stats-dump-period": string | *"10m"

	// The directory in which Raft RocksDB WAL files are stored, which is the absolute directory path for WAL. **Do not** set this configuration item to the same value as [`rocksdb.wal-dir`](#wal-dir). If this configuration item is not set, the log files are stored in the same directory as data. If there are two disks on the machine, storing RocksDB data and WAL logs on different disks can improve performance.
	"raftdb.wal-dir": string

	// Specifies how long the archived WAL files are retained. When the value is exceeded, the system deletes these files. Unit: second
	"raftdb.wal-ttl-seconds": float & >=0 | *0

	// The size limit of the archived WAL files. When the value is exceeded, the system deletes these files. Unit: B|KiB|MiB|GiB
	"raftdb.wal-size-limit": float & >=0 | *0

	// The maximum RocksDB WAL size in total
	// Default value:When `storage.engine="raft-kv"`, the default value is `"4GiB"`.When `storage.engine="partitioned-raft-kv"`, the default value is `1`.
	"raftdb.max-total-wal-size": string

	// Controls whether to enable the readahead feature during RocksDB compaction and specify the size of readahead data. If you use mechanical disks, it is recommended to set the value to `2MiB` at least. Unit: B|KiB|MiB|GiB
	"raftdb.compaction-readahead-size": float & >=0 | *0

	// The maximum buffer size used in WritableFileWrite. Unit: B|KiB|MiB|GiB
	"raftdb.writable-file-max-buffer-size": string | *"1MiB"

	// Determines whether to use `O_DIRECT` for both reads and writes in the background flush and compactions. The performance impact of this option: enabling `O_DIRECT` bypasses and prevents contamination of the OS buffer cache, but the subsequent file reads require re-reading the contents to the buffer cache.
	"raftdb.use-direct-io-for-flush-and-compaction": bool | *false

	// Controls whether to enable Pipelined Write. When this configuration is enabled, the previous Pipelined Write is used. When this configuration is disabled, the new Pipelined Commit mechanism is used.
	"raftdb.enable-pipelined-write": bool | *true

	// Controls whether to enable concurrent memtable write.
	"raftdb.allow-concurrent-memtable-write": bool | *true

	// The rate at which OS incrementally synchronizes files to disk while these files are being written asynchronously. Unit: B|KiB|MiB|GiB
	"raftdb.bytes-per-sync": string | *"1MiB"

	// The rate at which OS incrementally synchronizes WAL files to disk when the WAL files are being written. Unit: B|KiB|MiB|GiB
	"raftdb.wal-bytes-per-sync": string | *"512KiB"

	// The maximum size of Info logs. Unit: B|KiB|MiB|GiB
	"raftdb.info-log-max-size": string | *"1GiB"

	// The interval at which Info logs are truncated. If the value is `0s`, logs are not truncated.
	"raftdb.info-log-roll-time": string | *"0s"

	// The maximum number of Info log files kept in RaftDB
	"raftdb.info-log-keep-log-file-num": float & >=0 | *10

	// The directory in which Info logs are stored
	"raftdb.info-log-dir": string

	// Log levels of RaftDB
	"raftdb.info-log-level": string | *"info"

	// Determines whether to use Raft Engine to store Raft logs. When it is enabled, configurations of `raftdb` are ignored.
	"raft-engine.enable": bool | *true

	// The directory at which raft log files are stored. If the directory does not exist, it will be created when TiKV is started. If this configuration item is not set, `{data-dir}/raft-engine` is used. If there are multiple disks on your machine, it is recommended to store the data of Raft Engine on a different disk to improve TiKV performance.
	"raft-engine.dir": string

	// Specifies the threshold size of a log batch. A log batch larger than this configuration is compressed. If you set this configuration item to `0`, compression is disabled.
	"raft-engine.batch-compression-threshold": string | *"8KiB"

	// Specifies the maximum accumulative size of buffered writes. When this configuration value is exceeded, buffered writes are flushed to the disk. If you set this configuration item to `0`, incremental sync is disabled. Before v6.5.0, the default value is `"4MiB"`.
	"raft-engine.bytes-per-sync": string

	// Specifies the maximum size of log files. When a log file is larger than this value, it is rotated.
	"raft-engine.target-file-size": string | *"128MiB"

	// Specifies the threshold size of the main log queue. When this configuration value is exceeded, the main log queue is purged. This configuration can be used to adjust the disk space usage of Raft Engine.
	"raft-engine.purge-threshold": string | *"10GiB"

	// Determines how to deal with file corruption during recovery. Value options: `"absolute-consistency"`, `"tolerate-tail-corruption"`, `"tolerate-any-corruption"`
	"raft-engine.recovery-mode": string | *"tolerate-tail-corruption"

	// The minimum I/O size for reading log files during recovery.
	"raft-engine.recovery-read-block-size": string | *"16KiB"

	// The number of threads used to scan and recover log files.
	"raft-engine.recovery-threads": float & >=1 | *4

	// Specifies the limit on the memory usage of Raft Engine. When this configuration value is not set, 15% of the available system memory is used.
	// Default value: Total machine memory * 15%
	"raft-engine.memory-limit": string

	// Disable Raft Engine by setting [`enable`](/tikv-configuration-file.md#enable-1) to `false` and restart TiKV to make the configuration take effect. Set `format-version` to `1`. Enable Raft Engine by setting `enable` to `true` and restart TiKV to make the configuration take effect.
	"raft-engine.format-version": string

	// Determines whether to recycle stale log files in Raft Engine. When it is enabled, logically purged log files will be reserved for recycling. This reduces the long tail latency on write workloads.
	"raft-engine.enable-log-recycle": bool | *true

	// Determines whether to generate empty log files for log recycling in Raft Engine. When it is enabled, Raft Engine will automatically fill a batch of empty log files for log recycling during initialization, making log recycling effective immediately after initialization.
	"raft-engine.prefill-for-recycle": bool | *false

	// Sets the compression efficiency of the LZ4 algorithm used by Raft Engine when writing Raft log files. A lower value indicates faster compression speed but lower compression ratio. Range: `[1, 16]`
	"raft-engine.compression-level": string | *"1"

	// The path of the CA file
	"security.ca-path": string

	// The path of the Privacy Enhanced Mail (PEM) file that contains the X.509 certificate
	"security.cert-path": string

	// The path of the PEM file that contains the X.509 key
	"security.key-path": string

	// A list of acceptable X.509 Common Names in certificates presented by clients. Requests are permitted only when the presented Common Name is an exact match with one of the entries in the list.
	"security.cert-allowed-cn": [...string] | *[]

	// This configuration item enables or disables log redaction. If the configuration value is set to `true`, all user data in the log will be replaced by `?`.
	"security.redact-info-log": bool | *false

	// The encryption method for data files. Value options: "plaintext", "aes128-ctr", "aes192-ctr", "aes256-ctr", and "sm4-ctr" (supported since v6.3.0). A value other than "plaintext" means that encryption is enabled, in which case the master key must be specified.
	"security.encryption.data-encryption-method": string | *"plaintext"

	// Specifies how often TiKV rotates the data encryption key.
	"security.encryption.data-key-rotation-period": string | *"7d"

	// Enables the optimization to reduce I/O and mutex contention when TiKV manages the encryption metadata. To avoid possible compatibility issues when this configuration parameter is enabled (by default), see [Encryption at Rest - Compatibility between TiKV versions](/encryption-at-rest.md#compatibility-between-tikv-versions) for details.
	"security.encryption.enable-file-dictionary-log": bool | *true

	// Specifies the master key if encryption is enabled. To learn how to configure a master key, see [Encryption at Rest - Configure encryption](/encryption-at-rest.md#configure-encryption).
	"security.encryption.master-key": string

	// Specifies the old master key when rotating the new master key. The configuration format is the same as that of `master-key`. To learn how to configure a master key, see [Encryption at Rest - Configure encryption](/encryption-at-rest.md#configure-encryption).
	"security.encryption.previous-master-key": string

	// The number of threads to process RPC requests
	"import.num-threads": float & >=1 | *8

	// The window size of Stream channel. When the channel is full, the stream is blocked.
	"import.stream-channel-window": string | *"128"

	// Starting from v6.5.0, PITR supports directly accessing backup log files in memory and restoring data. This configuration item specifies the ratio of memory available for PITR to the total memory of TiKV. Value range: [0.0, 0.5]
	"import.memory-use-ratio": float & >=0.0 & <=0.5 | *"0.3"

	// The number of keys to be garbage-collected in one batch
	"gc.batch-keys": string | *"512"

	// The maximum bytes that GC worker can write to RocksDB in one second. If the value is set to `0`, there is no limit.
	"gc.max-write-bytes-per-sec": string | *"0"

	// Controls whether to enable the GC in Compaction Filter feature
	"gc.enable-compaction-filter": bool | *true

	// The garbage ratio threshold to trigger GC.
	"gc.ratio-threshold": string | *"1.1"

	// The number of GC threads when `enable-compaction-filter` is `false`.
	"gc.num-threads": string | *"1"

	// The number of worker threads to process backup. Value range: `[1, CPU]`
	"backup.num-threads": string | *"MIN"

	// The number of data ranges to back up in one batch
	"backup.batch-size": string | *"8"

	// The threshold of the backup SST file size. If the size of a backup file in a TiKV Region exceeds this threshold, the file is backed up to several files with the TiKV Region split into multiple Region ranges. Each of the files in the split Regions is the same size as `sst-max-size` (or slightly larger). For example, when the size of a backup file in the Region of `[a,e)` is larger than `sst-max-size`, the file is backed up to several files with regions `[a,b)`, `[b,c)`, `[c,d)` and `[d,e)`, and the size of `[a,b)`, `[b,c)`, `[c,d)` is the same as that of `sst-max-size` (or slightly larger).
	"backup.sst-max-size": string | *"144MiB"

	// Controls whether to limit the resources used by backup tasks to reduce the impact on the cluster when the cluster resource utilization is high. For more information, refer to [BR Auto-Tune](/br/br-auto-tune.md).
	"backup.enable-auto-tune": bool | *true

	// The part size used when you perform multipart upload to S3 during backup. You can adjust the value of this configuration to control the number of requests sent to S3. If data is backed up to S3 and the backup file is larger than the value of this configuration item, [multipart upload](https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPart.html) is automatically enabled. Based on the compression ratio, the backup file generated by a 96-MiB Region is approximately 10 MiB to 30 MiB.
	"backup.s3-multi-part-size": string | *"5MiB"

	// Specifies the location of the HDFS shell command and allows TiKV to find the shell command. This configuration item has the same effect as the environment variable `$HADOOP_HOME`.
	"backup.hadoop.home": string

	// Specifies the Linux user with which TiKV runs HDFS shell commands. If this configuration item is not set, TiKV uses the current linux user.
	"backup.hadoop.linux-user": string

	// Determines whether to enable log backup.
	"log-backup.enable": bool | *true

	// The size limit on backup log data to be stored. Note: Generally, the value of `file-size-limit` is greater than the backup file size displayed in external storage. This is because the backup files are compressed before being uploaded to external storage.
	"log-backup.file-size-limit": string | *"256MiB"

	// The quota of cache used for storing incremental scan data during log backup.
	"log-backup.initial-scan-pending-memory-quota": string | *"min"

	// The rate limit on throughput in an incremental data scan during log backup, which means the maximum amount of data that can be read from the disk per second. Note that if you only specify a number (for example, `60`), the unit is Byte instead of KiB.
	"log-backup.initial-scan-rate-limit": string | *"60MiB"

	// The maximum interval for writing backup data to external storage in log backup.
	"log-backup.max-flush-interval": string | *"3min"

	// The number of threads used in log backup. Value range: [2, 12]
	"log-backup.num-threads": string | *"CPU * 0.5"

	// The temporary path to which log files are written before being flushed to external storage.
	"log-backup.temp-path": string | *"${deploy-dir}/data/log-backup-temp"

	// The interval at which Resolved TS is calculated and forwarded.
	"cdc.min-ts-interval": string | *"1s"

	// The upper limit of memory usage by TiCDC old values.
	"cdc.old-value-cache-memory-quota": string | *"512MiB"

	// The upper limit of memory usage by TiCDC data change events.
	"cdc.sink-memory-quota": string | *"512MiB"

	// The maximum speed at which historical data is incrementally scanned.
	"cdc.incremental-scan-speed-limit": string | *"128MiB"

	// The number of threads for the task of incrementally scanning historical data.
	"cdc.incremental-scan-threads": string | *"4"

	// The maximum number of concurrent executions for the tasks of incrementally scanning historical data. Note: The value of `incremental-scan-concurrency` must be greater than or equal to that of `incremental-scan-threads`; otherwise, TiKV will report an error at startup.
	"cdc.incremental-scan-concurrency": string | *"6"

	// Determines whether to maintain the Resolved TS for all Regions.
	"resolved-ts.enable": bool | *true

	// The interval at which Resolved TS is calculated and forwarded.
	"resolved-ts.advance-ts-interval": string | *"20s"

	// The number of threads that TiKV uses to scan the MVCC (multi-version concurrency control) lock data when initializing the Resolved TS.
	"resolved-ts.scan-lock-pool-size": string | *"2"

	// The longest time that a pessimistic transaction in TiKV waits for other transactions to release the lock. If the time is out, an error is returned to TiDB, and TiDB retries to add a lock. The lock wait timeout is set by `innodb_lock_wait_timeout`.
	"pessimistic-txn.wait-for-lock-timeout": string | *"1s"

	// When pessimistic transactions release the lock, among all the transactions waiting for lock, only the transaction with the smallest `start_ts` is woken up. Other transactions will be woken up after `wake-up-delay-duration`.
	"pessimistic-txn.wake-up-delay-duration": string | *"20ms"

	// This configuration item enables the pipelined process of adding the pessimistic lock. With this feature enabled, after detecting that data can be locked, TiKV immediately notifies TiDB to execute the subsequent requests and write the pessimistic lock asynchronously, which reduces most of the latency and significantly improves the performance of pessimistic transactions. But there is a still low probability that the asynchronous write of the pessimistic lock fails, which might cause the failure of pessimistic transaction commits.
	"pessimistic-txn.pipelined": bool | *true

	// Enables the in-memory pessimistic lock feature. With this feature enabled, pessimistic transactions try to store their locks in memory, instead of writing the locks to disk or replicating the locks to other replicas. This improves the performance of pessimistic transactions. However, there is a still low probability that the pessimistic lock gets lost and causes the pessimistic transaction commits to fail. Note that `in-memory` takes effect only when the value of `pipelined` is `true`.
	"pessimistic-txn.in-memory": bool | *true

	// The maximum time that a single read or write request is forced to wait before it is processed in the foreground. Recommended setting: It is recommended to use the default value in most cases. If out of memory (OOM) or violent performance jitter occurs in the instance, you can set the value to 1S to make the request waiting time shorter than 1 second.
	"quota.max-delay-duration": string | *"500ms"

	// The soft limit on the CPU resources used by TiKV foreground to process read and write requests. Unit: millicpu (for example, `1500` means that the foreground requests consume 1.5v CPU). Recommended setting: For the instance with more than 4 cores, use the default value `0`. For the instance with 4 cores, setting the value to the range of `1000` and `1500` can make a balance. For the instance with 2 cores, keep the value smaller than `1200`.
	"quota.max-delay-duration": string | *"0"

	// Background Quota Limiter is an experimental feature introduced in TiDB v6.2.0, and it is **NOT** recommended to use it in the production environment. This feature is only suitable for environments with limited resources to ensure that TiKV can run stably in those environments. If you enable this feature in an environment with rich resources, performance degradation might occur when the amount of requests reaches a peak.
	"quota.max-delay-duration": string

	// The pre-allocated TSO cache size (in duration). Indicates that TiKV pre-allocates the TSO cache based on the duration specified by this configuration item. TiKV estimates the TSO usage based on the previous period, and requests and caches TSOs satisfying `alloc-ahead-buffer` locally. This configuration item is often used to increase the tolerance of PD failures when TiKV API V2 is enabled (`storage.api-version = 2`). Increasing the value of this configuration item might result in more TSO consumption and memory overhead of TiKV. To obtain enough TSOs, it is recommended to decrease the [`tso-update-physical-interval`](/pd-configuration-file.md#tso-update-physical-interval) configuration item of PD. According to the test, when `alloc-ahead-buffer` is in its default value, and the PD leader fails and switches to another node, the write request will experience a short-term increase in latency and a decrease in QPS (about 15%). To avoid the impact on the business, you can configure `tso-update-physical-interval = "1ms"` in PD and the following configuration items in TiKV:`causal-ts.alloc-ahead-buffer = "6s"``causal-ts.renew-batch-max-size = 65536``causal-ts.renew-batch-min-size = 2048`
	"causal-ts.alloc-ahead-buffer": string | *"3s"

	// The interval at which the locally cached timestamps are updated. At an interval of `renew-interval`, TiKV starts a batch of timestamp refresh and adjusts the number of cached timestamps according to the timestamp consumption in the previous period and the setting of [`alloc-ahead-buffer`](#alloc-ahead-buffer-new-in-v640). If you set this parameter to too large a value, the latest TiKV workload changes are not reflected in time. If you set this parameter to too small a value, the load of PD increases. If the write traffic is strongly fluctuating, if timestamps are frequently exhausted, and if write latency increases, you can set this parameter to a smaller value. At the same time, you should also consider the load of PD.
	"causal-ts.renew-interval": string | *"100ms"

	// The minimum number of TSOs in a timestamp request. TiKV adjusts the number of cached timestamps according to the timestamp consumption in the previous period. If only a few TSOs are required, TiKV reduces the TSOs requested until the number reaches `renew-batch-min-size`. If large bursty write traffic often occurs in your application, you can set this parameter to a larger value as appropriate. Note that this parameter is the cache size for a single tikv-server. If you set the parameter to too large a value and the cluster contains many tikv-servers, the TSO consumption will be too fast. In the **TiKV-RAW** \> **Causal timestamp** panel in Grafana, **TSO batch size** is the number of locally cached timestamps that has been dynamically adjusted according to the application workload. You can refer to this metric to adjust `renew-batch-min-size`.
	"causal-ts.renew-batch-min-size": string | *"100"

	// The maximum number of TSOs in a timestamp request. In a default TSO physical time update interval (`50ms`), PD provides at most 262144 TSOs. When requested TSOs exceed this number, PD provides no more TSOs. This configuration item is used to avoid exhausting TSOs and the reverse impact of TSO exhaustion on other businesses. If you increase the value of this configuration item to improve high availability, you need to decrease the value of [`tso-update-physical-interval`](/pd-configuration-file.md#tso-update-physical-interval) at the same time to get enough TSOs.
	"causal-ts.renew-batch-max-size": string | *"8192"

	// Controls whether to enable scheduling for user foreground read/write requests according to [Request Unit (RU)](/tidb-resource-control.md#what-is-request-unit-ru) of the corresponding resource groups. For information about TiDB resource groups and resource control, see [TiDB resource control](/tidb-resource-control.md). Enabling this configuration item only works when [`tidb_enable_resource_control](/system-variables.md#tidb_enable_resource_control-new-in-v660) is enabled on TiDB. When this configuration item is enabled, TiKV will use the priority queue to schedule the queued read/write requests from foreground users. The scheduling priority of a request is inversely related to the amount of resources already consumed by the resource group that receives this request, and positively related to the quota of the corresponding resource group.
	"resource-control.enabled": bool | *true

	// Controls the traffic threshold at which a Region is identified as a hotspot.
	// Default value:`30MiB` per second when [`region-split-size`] is greater than or equal to 4 GiB.
	"split.byte-threshold": string

	// Controls the QPS threshold at which a Region is identified as a hotspot.
	// Default value:`3000` when [`region-split-size`] is greater than or equal to 4 GiB.
	"split.qps-threshold": string

	// Controls the CPU usage threshold at which a Region is identified as a hotspot.
	// Default value:`0.25` when [`region-split-size`] is greater than or equal to 4 GiB.
	"split.region-cpu-overload-threshold-ratio": string

	// Controls whether to enable Heap Profiling to track the memory usage of TiKV.
	"memory.enable-heap-profiling": bool | *true

	// Specifies the amount of data sampled by Heap Profiling each time, rounding up to the nearest power of 2.
	"memory.profiling-sample-per-bytes": string | *"512KiB"

	...
}

configuration: #TIKVParameter & {}
