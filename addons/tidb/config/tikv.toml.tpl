## full example can be seen at:
## https://github.com/tikv/tikv/blob/release-7.5/etc/config-template.toml

## TiKV config template
##  Human-readable big numbers:
##   File size(based on byte, binary units): KB, MB, GB, TB, PB
##    e.g.: 1_048_576 = "1MB"
##   Time(based on ms): ms, s, m, h
##    e.g.: 78_000 = "1.3m"

## File to store slow logs.
## If "log-file" is set, but this is not set, the slow logs will be appeneded
## to "log-file". If both "log-file" and "slow-log-file" are not set, all logs
## will be appended to stderr.
slow-log-file = ""

## The minimum operation cost to output relative logs.
slow-log-threshold = "1s"

## Enable io snoop which utilize eBPF to get accurate disk io of TiKV
## It won't take effect when compiling without BCC_IOSNOOP=1.
enable-io-snoop = true

## Use abort when TiKV panic. By default TiKV will use _exit() on panic, in that case
## core dump file will not be generated, regardless of system settings.
## If this config is enabled, core dump files needs to be cleanup to avoid disk space
## being filled up.
abort-on-panic = false

## Memory usage limit for the TiKV instance. Generally it's unnecessary to configure it
## explicitly, in which case it will be set to 75% of total available system memory.
## Considering the behavior of `block-cache.capacity`, it means 25% memory is reserved for
## OS page cache.
##
## It's still unnecessary to configure it for deploying multiple TiKV nodes on a single
## physical machine. It will be calculated as `5/3 * block-cache.capacity`.
##
## For different system memory capacity, the default memory quota will be:
## * system=8G    block-cache=3.6G    memory-usage-limit=6G   page-cache=2G.
## * system=16G   block-cache=7.2G    memory-usage-limit=12G  page-cache=4G
## * system=32G   block-cache=14.4G   memory-usage-limit=24G  page-cache=8G
##
## So how can `memory-usage-limit` influence TiKV? When a TiKV's memory usage almost reaches
## this threshold, it can squeeze some internal components (e.g. evicting cached Raft entries)
## to release memory.
memory-usage-limit = "0B"

[quota]
## Quota is use to add some limitation for the read write flow and then
## gain predictable stable performance.
## CPU quota for these front requests can use, default value is 0, it means unlimited.
## The unit is millicpu but for now this config is approximate and soft limit.
foreground-cpu-time = 0
## Write bandwidth limitation for this TiKV instance, default value is 0 which means unlimited.
foreground-write-bandwidth = "0B"
## Read bandwidth limitation for this TiKV instance, default value is 0 which means unlimited.
foreground-read-bandwidth = "0B"
## CPU quota for these background requests can use, default value is 0, it means unlimited.
## The unit is millicpu but for now this config is approximate and soft limit.
background-cpu-time = 0
## Write bandwidth limitation for backgroud request for this TiKV instance, default value is 0 which means unlimited.
background-write-bandwidth = "0B"
## Read bandwidth limitation for background request for this TiKV instance, default value is 0 which means unlimited.
background-read-bandwidth = "0B"
## Limitation of max delay duration, default value is 0 which means unlimited.
max-delay-duration = "500ms"
## Whether to enable quota auto tune
enable-auto-tune = false

[log]
## Log levels: debug, info, warn, error, fatal.
## Note that `debug` is only available in development builds.
level = "info"
## log format, one of json, text. Default to text.
format = "text"
## Enable automatic timestamps in log output, if not set, it will be defaulted to true.
enable-timestamp = true

[log.file]
## Usually it is set through command line.
filename = ""
## max log file size in MB (upper limit to 4096MB)
max-size = 300
## max log file keep days
max-days = 0
## maximum number of old log files to retain
max-backups = 0

[memory]
## Whether enable the heap profiling which may have a bit performance overhead about 2% for the
## default sample rate.
enable-heap-profiling = true

## Average interval between allocation samples, as measured in bytes of allocation activity.
## Increasing the sampling interval decreases profile fidelity, but also decreases the
## computational overhead.
## The default sample interval is 512 KB. It only accepts power of two, otherwise it will be
## rounded up to the next power of two.
profiling-sample-per-bytes = "512KB"

## Configurations for the single thread pool serving read requests.
[readpool.unified]
## The minimal working thread count of the thread pool.
min-thread-count = 1

## The maximum working thread count of the thread pool.
## The default value is max(4, LOGICAL_CPU_NUM * 0.8).
max-thread-count = 4

## Size of the stack for each thread in the thread pool.
stack-size = "10MB"

## Max running tasks of each worker, reject if exceeded.
max-tasks-per-worker = 2000

[readpool.storage]
## Whether to use the unified read pool to handle storage requests.
use-unified-pool = true

## The following configurations only take effect when `use-unified-pool` is false.

## Size of the thread pool for high-priority operations.
high-concurrency = 4

## Size of the thread pool for normal-priority operations.
normal-concurrency = 4

## Size of the thread pool for low-priority operations.
low-concurrency = 4

## Max running high-priority operations of each worker, reject if exceeded.
max-tasks-per-worker-high = 2000

## Max running normal-priority operations of each worker, reject if exceeded.
max-tasks-per-worker-normal = 2000

## Max running low-priority operations of each worker, reject if exceeded.
max-tasks-per-worker-low = 2000

## Size of the stack for each thread in the thread pool.
stack-size = "10MB"

[readpool.coprocessor]
## Whether to use the unified read pool to handle coprocessor requests.
use-unified-pool = true

## The following configurations only take effect when `use-unified-pool` is false.

## Most read requests from TiDB are sent to the coprocessor of TiKV. high/normal/low-concurrency is
## used to set the number of threads of the coprocessor.
## If there are many read requests, you can increase these config values (but keep it within the
## number of system CPU cores). For example, for a 32-core machine deployed with TiKV, you can even
## set these config to 30 in heavy read scenarios.
## If CPU_NUM > 8, the default thread pool size for coprocessors is set to CPU_NUM * 0.8.

high-concurrency = 8
normal-concurrency = 8
low-concurrency = 8
max-tasks-per-worker-high = 2000
max-tasks-per-worker-normal = 2000
max-tasks-per-worker-low = 2000

[server]
## Listening address.
addr = "127.0.0.1:20160"

## Advertise listening address for client communication.
## If not set, `addr` will be used.
advertise-addr = ""

## Status address.
## This is used for reporting the status of TiKV directly through
## the HTTP address. Notice that there is a risk of leaking status
## information if this port is exposed to the public.
## Empty string means disabling it.
status-addr = "127.0.0.1:20180"

## Set the maximum number of worker threads for the status report HTTP service.
status-thread-pool-size = 1

## Compression type for gRPC channel: none, deflate or gzip.
grpc-compression-type = "none"

## Size of the thread pool for the gRPC server.
grpc-concurrency = 5

## The number of max concurrent streams/requests on a client connection.
grpc-concurrent-stream = 1024

## Limit the memory size can be used by gRPC. Default is unlimited.
## gRPC usually works well to reclaim memory by itself. Limit the memory in case OOM
## is observed. Note that limit the usage can lead to potential stall.
grpc-memory-pool-quota = "32G"

## The number of connections with each TiKV server to send Raft messages.
grpc-raft-conn-num = 1

## Amount to read ahead on individual gRPC streams.
grpc-stream-initial-window-size = "2MB"

## Time to wait before sending out a ping to check if server is still alive.
## This is only for communications between TiKV instances.
grpc-keepalive-time = "10s"

## Time to wait before closing the connection without receiving KeepAlive ping Ack.
grpc-keepalive-timeout = "3s"

## Set maximum message length in bytes that gRPC can send. `-1` means unlimited.
max-grpc-send-msg-len = 10485760

## How many snapshots can be sent concurrently.
concurrent-send-snap-limit = 32

## How many snapshots can be received concurrently.
concurrent-recv-snap-limit = 32

## Max allowed recursion level when decoding Coprocessor DAG expression.
end-point-recursion-limit = 1000

## Max time to handle Coprocessor requests before timeout.
end-point-request-max-handle-duration = "60s"

## Max bytes that snapshot can interact with disk in one second. It should be
## set based on your disk performance. Only write flow is considered, if
## partiioned-raft-kv is used, read flow is also considered and it will be estimated
## as read_size * 0.5 to get around errors from page cache.
snap-io-max-bytes-per-sec = "100MB"

## Whether to enable request batch.
enable-request-batch = true

## Attributes about this server, e.g. `{ zone = "us-west-1", disk = "ssd" }`.
labels = {}

## The working thread count of the background pool, which include the endpoint of and br, split-check,
## region thread and other thread of delay-insensitive tasks.
## The default value is 2 if the number of CPU cores is less than 16, otherwise 3.
background-thread-count = 2

## If handle time is larger than the threshold, it will print slow log in endpoint.
## The default value is 1s.
end-point-slow-log-threshold = "1s"

[storage]
## The path to RocksDB directory.
data-dir = "./"

## Specifies the engine type. This configuration can only be specified when creating a new cluster
## and cannot be modifies once being specified.
##
## Available types are:
## "raft-kv": The default engine type in versions earlier than TiDB v6.6.0.
## "partitioned-raft-kv": The new storage engine type introduced in TiDB v6.6.0.
engine = "raft-kv"

## The number of slots in Scheduler latches, which controls write concurrency.
## In most cases you can use the default value. When importing data, you can set it to a larger
## value.
scheduler-concurrency = 524288

## Scheduler's worker pool size, i.e. the number of write threads.
## It should be less than total CPU cores. When there are frequent write operations, set it to a
## higher value. More specifically, you can run `top -H -p tikv-pid` to check whether the threads
## named `sched-worker-pool` are busy.
scheduler-worker-pool-size = 4

## When the pending write bytes exceeds this threshold, the "scheduler too busy" error is displayed.
scheduler-pending-write-threshold = "100MB"

## For async commit transactions, it's possible to response to the client before applying prewrite
## requests. Enabling this can ease reduce latency when apply duration is significant, or reduce
## latency jittering when apply duration is not stable.
enable-async-apply-prewrite = false

## Reserve some space to ensure recovering the store from `no space left` must succeed.
## `max(reserve-space, capacity * 5%)` will be reserved exactly.
##
## Set it to 0 will cause no space is reserved at all. It's generally used for tests.
reserve-space = "5GB"

## Reserve some space for raft disk if raft disk is separated deployed with kv disk.
## `max(reserve-raft-space, raft disk capacity * 5%)` will be reserved exactly.
##
## Set it to 0 will cause no space is reserved at all. It's generally used for tests.
reserve-raft-space = "1GB"

## The maximum recovery time after rocksdb detects restorable background errors. When the data belonging
## to the data range is damaged, it will be reported to PD through heartbeat, and PD will add `remove-peer`
## operator to remove this damaged peer. When the damaged peer still exists in the current store, the
## corruption SST files remain, and the KV storage engine can still put new content normally, but it
## will return error when reading corrupt data range.
##
## If after this time, the peer where the corrupted data range located has not been removed from the
## current store, TiKV will panic.
##
## Set to 0 to disable this feature if you want to panic immediately when encountering such an error.
background-error-recovery-window = "1h"

## Block cache is used by RocksDB to cache uncompressed blocks. Big block cache can speed up read.
## It is recommended to turn on shared block cache. Since only the total cache size need to be
## set, it is easier to config. In most cases it should be able to auto-balance cache usage
## between column families with standard LRU algorithm.
[storage.block-cache]

## Size of the shared block cache. Normally it should be tuned to 30%-50% of system's total memory.
##
## To deploy multiple TiKV nodes on a single physical machine, configure this parameter explicitly.
## Otherwise, the OOM problem might occur in TiKV.
##
## When storage.engine is "raft-kv", default value is 45% of available system memory.
## When storage.engine is "partitioned-raft-kv", default value is 30% of available system memory.
capacity = "0B"

[storage.flow-control]
## Flow controller is used to throttle the write rate at scheduler level, aiming
## to substitute the write stall mechanism of RocksDB. It features in two points:
##   * throttle at scheduler, so raftstore and apply won't be blocked anymore
##   * better control on the throttle rate to avoid QPS drop under heavy write
##
## Support change dynamically.
## When enabled, it disables kvdb's write stall and raftdb's write stall(except memtable) and vice versa.
enable = true

## When the number of immutable memtables of kvdb reaches the threshold, the flow controller begins to work
memtables-threshold = 5

## When the number of SST files of level-0 of kvdb reaches the threshold, the flow controller begins to work
l0-files-threshold = 20

## When the number of pending compaction bytes of kvdb reaches the threshold, the flow controller begins to
## reject some write requests with `ServerIsBusy` error.
soft-pending-compaction-bytes-limit = "192GB"

## When the number of pending compaction bytes of kvdb reaches the threshold, the flow controller begins to
## reject all write requests with `ServerIsBusy` error.
hard-pending-compaction-bytes-limit = "1024GB"

[storage.io-rate-limit]
## Maximum I/O bytes that this server can write to or read from disk (determined by mode)
## in one second. Internally it prefers throttling background operations over foreground
## ones. This value should be set to the disk's optimal IO bandwidth, e.g. maximum IO
## bandwidth specified by cloud disk vendors.
##
## When set to zero, disk IO operations are not limited.
max-bytes-per-sec = "0MB"

## Determine which types of IO operations are counted and restrained below threshold.
## Three different modes are: write-only, read-only, all-io.
##
## Only write-only mode is supported for now.
mode = "write-only"

[pd]
## PD endpoints.
endpoints = ["127.0.0.1:2379"]

## The interval at which to retry a PD connection.
## Default is 300ms.
retry-interval = "300ms"

## If the client observes an error, it can can skip reporting it except every `n` times.
## Set to 1 to disable this feature.
## Default is 10.
retry-log-every = 10

## The maximum number of times to retry a PD connection initialization.
## Set to 0 to disable retry.
## Default is -1, meaning isize::MAX times.
retry-max-count = -1

[raftstore]
## Whether to enable Raft prevote.
## Prevote minimizes disruption when a partitioned node rejoins the cluster by using a two phase
## election.
prevote = true

## The path to RaftDB directory.
## If not set, it will be `{data-dir}/raft`.
## If there are multiple disks on the machine, storing the data of Raft RocksDB on a different disk
## can improve TiKV performance.
raftdb-path = ""

## Store capacity, i.e. max data size allowed.
## If it is not set, disk capacity is used.
capacity = 0

## Internal notify capacity.
## 40960 is suitable for about 7000 Regions. It is recommended to use the default value.
notify-capacity = 40960

## Maximum number of internal messages to process in a tick.
messages-per-tick = 4096

## Region heartbeat tick interval for reporting to PD.
pd-heartbeat-tick-interval = "60s"

## Store heartbeat tick interval for reporting to PD.
pd-store-heartbeat-tick-interval = "10s"

## The threshold of triggering Region split check.
## When Region size change exceeds this config, TiKV will check whether the Region should be split
## or not. To reduce the cost of scanning data in the checking process, you can set the value to
## 32MB during checking and set it back to the default value in normal operations.
region-split-check-diff = "6MB"

## The interval of triggering Region split check.
split-region-check-tick-interval = "10s"

## When the number of Raft entries exceeds the max size, TiKV rejects to propose the entry.
raft-entry-max-size = "8MB"

## Interval to compact unnecessary Raft log.
raft-log-compact-sync-interval = "2s"

## Interval to GC unnecessary Raft log.
raft-log-gc-tick-interval = "3s"

## Threshold to GC stale Raft log, must be >= 1.
raft-log-gc-threshold = 50

## When the entry count exceeds this value, GC will be forced to trigger.
raft-log-gc-count-limit = 73728

## When the approximate size of Raft log entries exceeds this value, GC will be forced trigger.
## It's recommanded to set it to 3/4 of `region-split-size`.
raft-log-gc-size-limit = "72MB"

## Old Raft logs could be reserved if `raft_log_gc_threshold` is not reached.
## GC them after ticks `raft_log_reserve_max_ticks` times.
raft_log_reserve_max_ticks = 6

## Raft engine is a replaceable component. For some implementations, it's necessary to purge
## old log files to recycle disk space ASAP.
raft-engine-purge-interval = "10s"

## How long the peer will be considered down and reported to PD when it hasn't been active for this
## time.
max-peer-down-duration = "10m"

## Interval to check whether to start manual compaction for a Region.
region-compact-check-interval = "5m"

## Number of Regions for each time to check.
region-compact-check-step = 100

## The minimum number of delete tombstones to trigger manual compaction.
region-compact-min-tombstones = 10000

## The minimum percentage of delete tombstones to trigger manual compaction.
## It should be set between 1 and 100. Manual compaction is only triggered when the number of
## delete tombstones exceeds `region-compact-min-tombstones` and the percentage of delete tombstones
## exceeds `region-compact-tombstones-percent`.
region-compact-tombstones-percent = 30

## The minimum number of duplicated MVCC keys to trigger manual compaction.
region-compact-min-redundant-rows = 50000

## The minimum percentage of duplicated MVCC keys to trigger manual compaction.
## It should be set between 1 and 100. Manual compaction is only triggered when the number of
## duplicated MVCC keys exceeds `region-compact-min-redundant-rows` and the percentage of duplicated MVCC keys
## exceeds `region-compact-redundant-rows-percent`.
region-compact-redundant-rows-percent = 20

## Interval to check whether to start a manual compaction for Lock Column Family.
## If written bytes reach `lock-cf-compact-bytes-threshold` for Lock Column Family, TiKV will
## trigger a manual compaction for Lock Column Family.
lock-cf-compact-interval = "10m"
lock-cf-compact-bytes-threshold = "256MB"

## Interval to check region whether the data is consistent.
consistency-check-interval = "0s"

## Interval to clean up import SST files.
cleanup-import-sst-interval = "10m"

## Use how many threads to handle log apply
apply-pool-size = 2

## Use how many threads to handle raft messages
store-pool-size = 2

## Use how many threads to handle raft io tasks
## If it is 0, it means io tasks are handled in store threads.
store-io-pool-size = 0

## When the size of raft db writebatch exceeds this value, write will be triggered.
raft-write-size-limit = "1MB"

## threads to generate raft snapshots
snap-generator-pool-size = 2

[coprocessor]
## When it is set to `true`, TiKV will try to split a Region with table prefix if that Region
## crosses tables.
## It is recommended to turn off this option if there will be a large number of tables created.
split-region-on-table = false

## One split check produces several split keys in batch. This config limits the number of produced
## split keys in one batch.
batch-split-limit = 10

## When Region [a,e) size exceeds `region_max_size`, it will be split into several Regions [a,b),
## [b,c), [c,d), [d,e) and the size of [a,b), [b,c), [c,d) will be `region_split_size` (or a
## little larger).
region-max-size = "144MB"
region-split-size = "96MB"

## When the number of keys in Region [a,e) exceeds the `region_max_keys`, it will be split into
## several Regions [a,b), [b,c), [c,d), [d,e) and the number of keys in [a,b), [b,c), [c,d) will be
## `region_split_keys`.
region-max-keys = 1440000
region-split-keys = 960000

## Set to "mvcc" to do consistency check for MVCC data, or "raw" for raw data.
consistency-check-method = "mvcc"

[coprocessor-v2]
## Path to the directory where compiled coprocessor plugins are located.
## Plugins in this directory will be automatically loaded by TiKV.
## If the config value is not set, the coprocessor plugin will be disabled.
coprocessor-plugin-directory = "./coprocessors"

[raftdb]
max-background-jobs = 4
max-sub-compactions = 2
max-open-files = 40960
max-manifest-file-size = "20MB"
create-if-missing = true

stats-dump-period = "10m"

## Raft RocksDB WAL directory.
## This config specifies the absolute directory path for WAL.
## If it is not set, the log files will be in the same directory as data.
## If there are two disks on the machine, storing RocksDB data and WAL logs on different disks can
## improve performance.
## Do not set this config the same as `rocksdb.wal-dir`.
wal-dir = ""

compaction-readahead-size = 0
writable-file-max-buffer-size = "1MB"
use-direct-io-for-flush-and-compaction = false
enable-pipelined-write = true
allow-concurrent-memtable-write = true
bytes-per-sync = "1MB"
wal-bytes-per-sync = "512KB"

info-log-max-size = "1GB"
info-log-roll-time = "0s"
info-log-keep-log-file-num = 10
info-log-dir = ""
info-log-level = "info"

[raftdb.defaultcf]
## Recommend to set it the same as `rocksdb.defaultcf.compression-per-level`.
compression-per-level = ["no", "no", "lz4", "lz4", "lz4", "zstd", "zstd"]
block-size = "64KB"

## Recommend to set it the same as `rocksdb.defaultcf.write-buffer-size`.
write-buffer-size = "128MB"
max-write-buffer-number = 5
min-write-buffer-number-to-merge = 1

## Recommend to set it the same as `rocksdb.defaultcf.max-bytes-for-level-base`.
max-bytes-for-level-base = "512MB"
target-file-size-base = "8MB"

level0-file-num-compaction-trigger = 4
level0-slowdown-writes-trigger = 20
level0-stop-writes-trigger = 20
cache-index-and-filter-blocks = true
pin-l0-filter-and-index-blocks = true
compaction-pri = "by-compensated-size"
soft-pending-compaction-bytes-limit = "192GB"
hard-pending-compaction-bytes-limit = "1000GB"
read-amp-bytes-per-bit = 0
dynamic-level-bytes = true
optimize-filters-for-hits = true
enable-compaction-guard = false
format-version = 2
prepopulate-block-cache = "disabled"
checksum = "crc32c"
max-compactions = 0

[raft-engine]
## Determines whether to use Raft Engine to store raft logs. When it is
## enabled, configurations of `raftdb` are ignored.
enable = true

## The directory at which raft log files are stored. If the directory does not
## exist, it will be created when TiKV is started.
##
## When this configuration is not set, `{data-dir}/raft-engine` is used.
##
## If there are multiple disks on your machine, it is recommended to store the
## data of Raft Engine on a different disk to improve TiKV performance.
dir = ""

## Specifies the threshold size of a log batch. A log batch larger than this
## configuration is compressed.
##
## If you set this configuration item to `0`, compression is disabled.
batch-compression-threshold = "8KB"

## Specifies the maximum size of log files. When a log file is larger than this
## value, it is rotated.
target-file-size = "128MB"

## Specifies the threshold size of the main log queue. When this configuration
## value is exceeded, the main log queue is purged.
##
## This configuration can be used to adjust the disk space usage of Raft
## Engine.
purge-threshold = "10GB"

## Determines how to deal with file corruption during recovery.
##
## Candidates:
##   absolute-consistency
##   tolerate-tail-corruption
##   tolerate-any-corruption
recovery-mode = "tolerate-tail-corruption"

## The minimum I/O size for reading log files during recovery.
##
## Default: "16KB". Minimum: "512B".
recovery-read-block-size = "16KB"

## The number of threads used to scan and recover log files.
##
## Default: 4. Minimum: 1.
recovery-threads = 4

## Memory usage limit for Raft Engine.
## When it's not set, 15% of available system memory will be used.
memory-limit = "1GB"

## Version of the log file in Raft Engine.
##
## Candidates:
##   1: Can be read by TiKV release 6.1 and above.
##   2: Can be read by TiKV release 6.3 and above. Supports log recycling.
##
## Default: 2.
format-version = 2

## Whether to recycle stale log files in Raft Engine.
## If `true`, logically purged log files will be reserved for recycling.
## Only available for `format-version` >= 2. This option is only
## available when TiKV >= 6.3.x.
##
## Default: true.
enable-log-recycle = true

## Whether to prepare log files for recycling when start.
## If `true`, batch empty log files will be prepared for recycling when
## starting engine.
## Only available for `enable-log-reycle` is true.
##
## Default: false
prefill-for-recycle = false

[security]
## The path for TLS certificates. Empty string means disabling secure connections.
ca-path = ""
cert-path = ""
key-path = ""
cert-allowed-cn = []
#
## Avoid outputing data (e.g. user keys) to info log. It currently does not avoid printing
## user data altogether, but greatly reduce those logs.
## Default is false.
redact-info-log = false

## Configurations for encryption at rest. Experimental.
[security.encryption]
## Encryption method to use for data files.
## Possible values are "plaintext", "aes128-ctr", "aes192-ctr", "aes256-ctr" and "sm4-ctr".
## Value other than "plaintext" means encryption is enabled, in which case
## master key must be specified.
data-encryption-method = "plaintext"

## Specifies how often TiKV rotates data encryption key.
data-key-rotation-period = "7d"

## Enable an optimization to reduce IO and mutex contention for encryption metadata management.
## Once the option is turned on (which is the default after 4.0.9), the data format is not
## compatible with TiKV <= 4.0.8. In order to downgrade to TiKV <= 4.0.8, one can turn off this
## option and restart TiKV, after which TiKV will convert the data format to be compatible with
## previous versions.
enable-file-dictionary-log = true

## Specifies master key if encryption is enabled. There are three types of master key:
##
##   * "plaintext":
##
##     Plaintext as master key means no master key is given and only applicable when
##     encryption is not enabled, i.e. data-encryption-method = "plaintext". This type doesn't
##     have sub-config items. Example:
##
##     [security.encryption.master-key]
##     type = "plaintext"
##
##   * "kms":
##
##     Use a KMS service to supply master key. Currently only AWS KMS is supported. This type of
##     master key is recommended for production use. Example:
##
##     [security.encryption.master-key]
##     type = "kms"
##     ## KMS CMK key id. Must be a valid KMS CMK where the TiKV process has access to.
##     ## In production is recommended to grant access of the CMK to TiKV using IAM.
##     key-id = "1234abcd-12ab-34cd-56ef-1234567890ab"
##     ## AWS region of the KMS CMK.
##     region = "us-west-2"
##     ## (Optional) AWS KMS service endpoint. Only required when non-default KMS endpoint is
##     ## desired.
##     endpoint = "https://kms.us-west-2.amazonaws.com"
##
##   * "file":
##
##     Supply a custom encryption key stored in a file. It is recommended NOT to use in production,
##     as it breaks the purpose of encryption at rest, unless the file is stored in tempfs.
##     The file must contain a 256-bits (32 bytes, regardless of key length implied by
##     data-encryption-method) key encoded as hex string and end with newline ("\n"). Example:
##
##     [security.encryption.master-key]
##     type = "file"
##     path = "/path/to/master/key/file"
##
[security.encryption.master-key]
type = "plaintext"

## Specifies the old master key when rotating master key. Same config format as master-key.
## The key is only access once during TiKV startup, after that TiKV do not need access to the key.
## And it is okay to leave the stale previous-master-key config after master key rotation.
[security.encryption.previous-master-key]
type = "plaintext"

[import]
## Number of threads to handle RPC requests.
num-threads = 8

## Stream channel window size, stream will be blocked on channel full.
stream-channel-window = 128

[backup]
## Number of threads to perform backup tasks.
## The default value is set to min(CPU_NUM * 0.5, 8).
num-threads = 8

## Number of ranges to backup in one batch.
batch-size = 8

## When Backup region [a,e) size exceeds `sst-max-size`, it will be backuped into several Files [a,b),
## [b,c), [c,d), [d,e) and the size of [a,b), [b,c), [c,d) will be `sst-max-size` (or a
## little larger).
sst-max-size = "144MB"

## Automatically reduce the number of backup threads when the current workload is high,
## in order to reduce impact on the cluster's performance during back up.
enable-auto-tune = true

[log-backup]
## Number of threads to perform backup stream tasks.
## The default value is CPU_NUM * 0.5, and limited to [2, 12].
num-threads = 8

## enable this feature. TiKV will starts watch related tasks in PD. and backup kv changes to storage accodring to task.
## The default value is false.
enable = true

[backup.hadoop]
## let TiKV know how to find the hdfs shell command.
## Equivalent to the $HADOOP_HOME enviroment variable.
home = ""

## TiKV will run the hdfs shell command under this linux user.
## TiKV will use the current linux user if not provided.
linux-user = ""

[pessimistic-txn]
## The default and maximum delay before responding to TiDB when pessimistic
## transactions encounter locks
wait-for-lock-timeout = "1s"

## If more than one transaction is waiting for the same lock, only the one with smallest
## start timestamp will be waked up immediately when the lock is released. Others will
## be waked up after `wake_up_delay_duration` to reduce contention and make the oldest
## one more likely acquires the lock.
wake-up-delay-duration = "20ms"

## Enable pipelined pessimistic lock, only effect when processing perssimistic transactions.
## Enabling this will improve performance, but slightly increase the transaction failure rate
pipelined = true

## Enable in-memory pessimistic lock, only effect when processing perssimistic transactions.
## Enabling this will improve performance, but slightly increase the transaction failure rate.
## It only takes effect when `pessimistic-txn.pipelined` is also set to true.
in-memory = true

[gc]
## The number of keys to GC in one batch.
batch-keys = 512

## Max bytes that GC worker can write to rocksdb in one second.
## If it is set to 0, there is no limit.
max-write-bytes-per-sec = "0"

## Enable GC by compaction filter or not.
enable-compaction-filter = true

## Garbage ratio threshold to trigger a GC.
ratio-threshold = 1.1