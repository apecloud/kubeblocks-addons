
{{- $time_zone := getEnvByName ( getContainerByName $.podSpec.containers "storaged" ) "DEFAULT_TIMEZONE" }}
{{- $storaged_container := getContainerByName $.podSpec.containers "storaged" }}
{{- $phy_memory := getContainerMemory $storaged_container }}
{{- $phy_cpu := getContainerCPU $storaged_container }}

{{- /* Compute resource-adaptive parameters, keep the values within the constraint range:
  rocksdb_block_cache [1,102400]MB, num_io_threads [1,256], num_worker_threads [1,256],
  max_concurrent_subtasks [1,1000], memory_tracker_untracked_reserved_memory_mb [0,102400] */}}
{{- $block_cache_mb := 4 }}
{{- $num_io_threads := 16 }}
{{- $num_worker_threads := 32 }}
{{- $max_concurrent_subtasks := 10 }}
{{- $untracked_memory_mb := 50 }}
{{- $write_buffer_size := 67108864 }}
{{- $max_bytes_level_base := 268435456 }}
{{- $max_background_jobs := 4 }}

{{- if gt $phy_cpu 0 }}
{{- /* 1 background job per 2 CPU cores, at least 4 and at most 32 */}}
{{- $max_background_jobs = max 4 ( min ( div ( int $phy_cpu ) 2 ) 32 ) }}
{{- $num_io_threads = max 16 ( min ( int $phy_cpu ) 256 ) }}
{{- $num_worker_threads = max 32 ( min ( int $phy_cpu ) 256 ) }}
{{- $max_concurrent_subtasks = max 10 ( min ( div ( int $phy_cpu ) 4 ) 100 ) }}
{{- end }}

{{- if gt $phy_memory 0 }}
{{- /* block cache = 20% of memory, unit MB (resident memory, NOT covered by memory tracker) */}}
{{- $block_cache_mb = max 4 ( min ( div ( div ( mul ( int $phy_memory ) 2 ) 10 ) 1048576 ) 102400 ) }}
{{- /* reserve 20% of memory for block cache + memtable + system, at least 50MB.
     The memory tracker only limits query memory, so the resident RocksDB memory
     must be excluded from the trackable memory to avoid OOM. */}}
{{- $untracked_memory_mb = max 50 ( min ( div ( div ( int $phy_memory ) 5 ) 1048576 ) 102400 ) }}
{{- /* memtable = 1/128 of memory (bounded 64MB~512MB), level base = memtable * 4 */}}
{{- $write_buffer_size = max 67108864 ( min ( div ( int $phy_memory ) 128 ) 536870912 ) }}
{{- $max_bytes_level_base = mulf $write_buffer_size 4 | int }}
{{- end }}

########## basics ##########
# Whether to run as a daemon process
--daemonize=true
# The file to host the process id
--pid_file=pids/nebula-storaged.pid
# Whether to use the configuration obtained from the configuration file
--local_config=true
--timezone_name={{ $time_zone }}

########## logging ##########
# The directory to host logging files
--log_dir=logs
# Log level, 0, 1, 2, 3 for INFO, WARNING, ERROR, FATAL respectively
--minloglevel=0
# Verbose log level, 1, 2, 3, 4, the higher of the level, the more verbose of the logging
--v=0
# Maximum seconds to buffer the log messages
--logbufsecs=0
# Whether to redirect stdout and stderr to separate output files
--redirect_stdout=true
# Destination filename of stdout and stderr, which will also reside in log_dir.
--stdout_log_file=storaged-stdout.log
--stderr_log_file=storaged-stderr.log
# Copy log messages at or above this level to stderr in addition to logfiles. The numbers of severity levels INFO, WARNING, ERROR, and FATAL are 0, 1, 2, and 3, respectively.
--stderrthreshold=3
# Wether logging files' name contain time stamp.
--timestamp_in_logfile_name=true

########## networking ##########
# Comma separated Meta server addresses
--meta_server_addrs={{ .NEBULA_METAD_SVC }}
# Local IP used to identify the nebula-storaged process.
# Change it to an address other than loopback if the service is distributed or
# will be accessed remotely.
#--local_ip=127.0.0.1
# Storage daemon listening port
--port=9779
# HTTP service ip
--ws_ip=0.0.0.0
# HTTP service port
--ws_http_port=19779
# heartbeat with meta service
--heartbeat_interval_secs=10

######### Raft #########
# Raft election timeout
--raft_heartbeat_interval_secs=30
# RPC timeout for raft client (ms)
--raft_rpc_timeout_ms=500
# recycle Raft WAL
--wal_ttl=14400
# whether send raft snapshot by files via http
#--snapshot_send_files=true

########## Disk ##########
# Root data path. Split by comma. e.g. --data_path=/disk1/path1/,/disk2/path2/
# One path per Rocksdb instance.
--data_path=data/storage

# Minimum reserved bytes of each data path
--minimum_reserved_bytes=268435456

# The default reserved bytes for one batch operation
--rocksdb_batch_size=4096
# The default block cache size used in BlockBasedTable.
# The unit is MB.
--rocksdb_block_cache={{ $block_cache_mb }}
# Disable page cache to better control memory used by rocksdb.
# Caution: Make sure to allocate enough block cache if disabling page cache!
--disable_page_cache=false
# The type of storage engine, rocksdb, memory, etc.
--engine_type=rocksdb

# Compression algorithm, options: no,snappy,lz4,lz4hc,zlib,bzip2,zstd
# For the sake of binary compatibility, the default value is snappy.
# Recommend to use:
#   * lz4 to gain more CPU performance, with the same compression ratio with snappy
#   * zstd to occupy less disk space
#   * lz4hc for the read-heavy write-light scenario
--rocksdb_compression=lz4

# Set different compressions for different levels
# For example, if --rocksdb_compression is snappy,
# "no:no:lz4:lz4::zstd" is identical to "no:no:lz4:lz4:snappy:zstd:snappy"
# In order to disable compression for level 0/1, set it to "no:no"
--rocksdb_compression_per_level=

# Whether or not to enable rocksdb's statistics, disabled by default
--enable_rocksdb_statistics=false

# Statslevel used by rocksdb to collection statistics, optional values are
#   * kExceptHistogramOrTimers, disable timer stats, and skip histogram stats
#   * kExceptTimers, Skip timer stats
#   * kExceptDetailedTimers, Collect all stats except time inside mutex lock AND time spent on compression.
#   * kExceptTimeForMutex, Collect all stats except the counters requiring to get time inside the mutex lock.
#   * kAll, Collect all stats
--rocksdb_stats_level=kExceptHistogramOrTimers

# Whether or not to enable rocksdb's prefix bloom filter, enabled by default.
--enable_rocksdb_prefix_filtering=true
# Whether or not to enable rocksdb's whole key bloom filter, disabled by default.
--enable_rocksdb_whole_key_filtering=false

############## rocksdb Options ##############
# rocksdb DBOptions in json, each name and value of option is a string, given as "option_name":"option_value" separated by comma
--rocksdb_db_options={"max_background_jobs":"{{ $max_background_jobs }}"}
# rocksdb ColumnFamilyOptions in json, each name and value of option is string, given as "option_name":"option_value" separated by comma
--rocksdb_column_family_options={"write_buffer_size":"{{ $write_buffer_size }}","max_write_buffer_number":"4","max_bytes_for_level_base":"{{ $max_bytes_level_base }}"}
# rocksdb BlockBasedTableOptions in json, each name and value of option is string, given as "option_name":"option_value" separated by comma
--rocksdb_block_based_table_options={"block_size":"8192"}

############## storage cache ##############
# Whether to enable storage cache
#--enable_storage_cache=false
# Total capacity reserved for storage in memory cache in MB
#--storage_cache_capacity=0
# Estimated number of cache entries on this storage node in base 2 logarithm. E.g., in case of 20, the estimated number of entries will be 2^20.
# A good estimate can be log2(#vertices on this storage node). The maximum allowed is 31.
#--storage_cache_entries_power=20

# Whether to add vertex pool in cache. Only valid when storage cache is enabled.
#--enable_vertex_pool=false
# Vertex pool size in MB
#--vertex_pool_capacity=50
# TTL in seconds for vertex items in the cache
#--vertex_item_ttl=300

# Whether to add negative pool in cache. Only valid when storage cache is enabled.
#--enable_negative_pool=false
# Negative pool size in MB
#--negative_pool_capacity=50
# TTL in seconds for negative items in the cache
#--negative_item_ttl=300

############### misc ####################
# Whether turn on query in multiple thread
--query_concurrently=true
# Whether remove outdated space data
--auto_remove_invalid_space=true
# Network IO threads number
--num_io_threads={{ $num_io_threads }}
# Worker threads number to handle request
--num_worker_threads={{ $num_worker_threads }}
# Maximum subtasks to run admin jobs concurrently
--max_concurrent_subtasks={{ $max_concurrent_subtasks }}
# The rate limit in bytes when leader synchronizes snapshot data
--snapshot_part_rate_limit=10485760
# The amount of data sent in each batch when leader synchronizes snapshot data
--snapshot_batch_size=1048576
# The rate limit in bytes when leader synchronizes rebuilding index
--rebuild_index_part_rate_limit=4194304
# The amount of data sent in each batch when leader synchronizes rebuilding index
--rebuild_index_batch_size=1048576

############## non-volatile cache ##############
# Cache file location
--nv_cache_path=/tmp/cache
# Cache file size in MB
--nv_cache_size=0
# DRAM part size of non-volatile cache in MB
--nv_dram_size=50
# DRAM part bucket power. The value is a logarithm with a base of 2. Optional values are 0-32.
--nv_bucket_power=20
# DRAM part lock power. The value is a logarithm with a base of 2. The recommended value is max(1, nv_bucket_power - 10).
--nv_lock_power=10

########## Black box ########
# Enable black box
--ng_black_box_switch=true
# Black box log folder
--ng_black_box_home=black_box
# Black box dump metrics log period
--ng_black_box_dump_period_seconds=5
# Black box log files expire time
--ng_black_box_file_lifetime_seconds=1800

########## memory tracker ##########
# trackable memory ratio (trackable_memory / (total_memory - untracked_reserved_memory) )
# 0.6 leaves headroom for the resident RocksDB memory (block cache + memtable)
--memory_tracker_limit_ratio=0.9
# untracked reserved memory in Mib
--memory_tracker_untracked_reserved_memory_mb={{ $untracked_memory_mb }}

# enable log memory tracker stats periodically
--memory_tracker_detail_log=false
# log memory tacker stats interval in milliseconds
--memory_tracker_detail_log_interval_ms=60000

# enable memory background purge (if jemalloc is used)
--memory_purge_enabled=true
# memory background purge interval in seconds
--memory_purge_interval_seconds=10

########## container/cgroup ##########
# Run inside a container, memory tracker reads the cgroup limit instead of host /proc/meminfo
--containerized=true
--cgroup_v2_controllers=/sys/fs/cgroup/cgroup.controllers
--cgroup_v2_memory_stat_path=/sys/fs/cgroup/memory.stat
--cgroup_v2_memory_max_path=/sys/fs/cgroup/memory.max
--cgroup_v2_memory_current_path=/sys/fs/cgroup/memory.current