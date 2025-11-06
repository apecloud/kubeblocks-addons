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

#NebulaStoragedParameter: {
    // Whether to run as a daemon process.
	"--daemonize": bool | *true

	// File path to store the process ID (PID).
	"--pid_file": string | *"pids/nebula-storaged.pid"

	// Time zone name, e.g., UTC+08:00 for China Standard Time.
	// Format reference: https://www.gnu.org/software/libc/manual/html_node/TZ-Variable.html
	// Default value: UTC+00:00:00 if not specified.
	"--timezone_name": string | *"UTC+00:00:00"

	// Whether to load configuration from local config file.
	"--local_config": bool | *true

    // Directory to store Graph service logs.
	// It is recommended to place logs and data on different disks.
	"--log_dir": string | *"logs"

	// Minimum log level to record (INFO=0, WARNING=1, ERROR=2, FATAL=3).
	// Setting to 4 disables all logs.
	// Suggested values:
	//   - 0 (INFO) for debugging
	//   - 1 (WARNING) for production
	// dynamic: true
	"--minloglevel": int & >=0 & <=4 | *0

	// VLOG verbosity level. Records VLOG messages at or below this level.
	// Valid values: 0, 1, 2, 3, 4, 5
	// dynamic: true
	"--v": int & >=0 & <=5 | *0

	// Maximum time (in seconds) to buffer logs before writing to file.
	// 0 means real-time logging.
	"--logbufsecs": number & >=0 | *0

	// Whether to redirect stdout/stderr to separate log files.
	"--redirect_stdout": bool | *true

	// File name for standard output logs.
	"--stdout_log_file": string | *"graphd-stdout.log"

	// File name for standard error logs.
	"--stderr_log_file": string | *"graphd-stderr.log"

	// Minimum log level that will be copied to stderr.
	// Valid values: 0 (INFO), 1 (WARNING), 2 (ERROR), 3 (FATAL)
	"--stderrthreshold": int & >=0 & <=3 | *3

	// Whether to include timestamp in log file names.
	"--timestamp_in_logfile_name": bool | *true

	// Comma-separated list of all Meta service addresses (IP/hostname:port).
    // Example: "meta1:9559,meta2:9559"
    "--meta_server_addrs": string | *"127.0.0.1:9559"

    // Local IP address used to identify this graphd instance.
    // For distributed clusters or remote access, change it accordingly.
    "--local_ip": string | *"127.0.0.1"

    // RPC port for the Graph service.
    "--port": int & >=1024 & <=65535 | *9669

    // IP address for HTTP service (metrics, REST API).
    "--ws_ip": string | *"0.0.0.0"

    // Port for HTTP service (metrics, REST API).
    "--ws_http_port": int & >=1024 & <=65535 | *19669

    // Default heartbeat interval between services (in seconds).
    // Must be consistent across all services; otherwise, the system may malfunction.
    "--heartbeat_interval_secs": int & >0 | *10

    // Raft heartbeat interval in seconds.
    // This should be consistent across all services.
    "--raft_heartbeat_interval_secs": int & >=1 & <=86400 | *30

    // Raft RPC timeout in milliseconds.
    "--raft_rpc_timeout_ms": int & >=10 & <=300000 | *500

    // Time-to-live (TTL) of Write Ahead Logs (WAL) in seconds.
    "--wal_ttl": int & >=60 & <=259200 | *14400

    // Data storage paths, separated by commas.
    // Each RocksDB instance corresponds to one path. Do NOT change this arbitrarily.
    "--data_path": string | *"data/storage"

    // Minimum reserved bytes per data path. If free space is below this value,
    // write operations may fail. Unit: bytes.
    "--minimum_reserved_bytes": int & >=1048576 | *268435456

    // Batch operation buffer size in bytes.
    "--rocksdb_batch_size": int & >=1024 & <=1048576 | *4096

    // Default block cache size for BlockBasedTable. Unit: megabytes.
    "--rocksdb_block_cache": int & >=1 & <=102400 | *4

    // Whether to disable the OS page cache for RocksDB.
    // false means allow using page cache.
    // true means disable it, and you must set sufficient block cache size.
    "--disable_page_cache": bool | *false

    // Storage engine type. Only "rocksdb" is supported currently.
    "--engine_type": string | *"rocksdb"

    // Compression algorithm used for all levels.
    // Valid values: no, snappy, lz4, lz4hc, zlib, bzip2, zstd
    // This setting can be overridden by rocksdb_compression_per_level.
    "--rocksdb_compression": string & "no" | "snappy" | "lz4" | "lz4hc" | "zlib" | "bzip2" | "zstd" | *"lz4"

    // Compression algorithms for each level.
    // Format example: "no:no:lz4:lz4:snappy:zstd:snappy"
    // If not set for a level, use rocksdb_compression.
    "--rocksdb_compression_per_level": string

    // Whether to enable RocksDB statistics collection.
    "--enable_rocksdb_statistics": bool | *false

    // Statistics level for RocksDB.
    // Valid values:
    //   kExceptHistogramOrTimers
    //   kExceptTimers
    //   kExceptDetailedTimers
    //   kExceptTimeForMutex
    //   kAll
    "--rocksdb_stats_level": string & ("kExceptHistogramOrTimers" | "kExceptTimers" | "kExceptDetailedTimers" | "kExceptTimeForMutex" | "kAll") | *"kExceptHistogramOrTimers"

    // Whether to enable prefix bloom filter.
    // Improves graph traversal performance but increases memory usage.
    "--enable_rocksdb_prefix_filtering": bool | *true

    // Whether to enable whole key bloom filter.
    "--enable_rocksdb_whole_key_filtering": bool | *false

    // Length of the key prefix for filtering.
    // Valid values: 12 (partition ID + vertex ID), 16 (partition ID + vertex ID + Tag/Edge type ID)
    // Unit: bytes
    "--rocksdb_filtering_prefix_length": int & (12 | 16) | *12

    // Whether to enable partitioned index filter to reduce bloom filter memory usage.
    // May reduce read performance on random seeks.
    "--enable_partitioned_index_filter": bool | *false

    // RocksDB database options.
    // Format: a JSON object with key-value pairs of RocksDB DBOptions.
    // supported options:
    // max_total_wal_size
    // delete_obsolete_files_period_micros
    // max_background_jobs
    // stats_dump_period_sec
    // compaction_readahead_size
    // writable_file_max_buffer_size
    // bytes_per_sync
    // wal_bytes_per_sync
    // delayed_write_rate
    // avoid_flush_during_shutdown
    // max_open_files
    // stats_persist_period_sec
    // stats_history_buffer_size
    // strict_bytes_per_sync
    // enable_rocksdb_prefix_filtering
    // enable_rocksdb_whole_key_filtering
    // rocksdb_filtering_prefix_length
    // num_compaction_threads
    // rate_limit
    "--rocksdb_db_options": string | *"{}"

	// RocksDB column family options.
	// Format: a JSON object with key-value pairs of RocksDB ColumnFamilyOptions
	// supported options:
	// write_buffer_size
    // max_write_buffer_number
    // level0_file_num_compaction_trigger
    // level0_slowdown_writes_trigger
    // level0_stop_writes_trigger
    // target_file_size_base
    // target_file_size_multiplier
    // max_bytes_for_level_base
    // max_bytes_for_level_multiplier
    // disable_auto_compactions
	"--rocksdb_column_family_options": string | *'{"write_buffer_size":"67108864", "max_write_buffer_number":"4","max_bytes_for_level_base":"268435456"}'

    // RocksDB block-based table options.
    // Format: a JSON object with key-value pairs of RocksDB BlockBasedTableOptions.
    "--rocksdb_block_based_table_options": string | *'{"block_size":"8192"}'

    // Performance and network configuration for NebulaGraph storaged process
    // Whether to enable multi-threaded query execution.
    // Improves single query latency, but may reduce overall throughput under high pressure.
    "--query_concurrently": bool | *true

    // Whether to automatically remove all data in the space when dropping a graph space.
    "--auto_remove_invalid_space": bool | *true

    // Number of I/O threads used for sending and receiving RPC requests.
    "--num_io_threads": int & >=1 & <=256 | *16

    // Maximum number of active connections across all network threads.
    // 0 means no limit. Per thread limit = max_connections / num_netio_threads
    "--num_max_connections": int & >=0 | *0

    // Number of worker threads for Storage's RPC service.
    "--num_worker_threads": int & >=1 & <=256 | *32

    // Max number of subtasks that TaskManager can execute concurrently.
    "--max_concurrent_subtasks": int & >=1 & <=1000 | *10

    // Rate limit for Raft leader to send snapshot data to other members (in bytes/sec).
    "--snapshot_part_rate_limit": int & >=1024 & <=1073741824 | *10485760

    // Batch size for each snapshot data transfer (in bytes).
    "--snapshot_batch_size": int & >=4096 & <=16777216 | *1048576

    // Rate limit for index data sync during index rebuild (in bytes/sec).
    "--rebuild_index_part_rate_limit": int & >=1024 & <=1073741824 | *4194304

    // Batch size for each index data transfer during index rebuild (in bytes).
    "--rebuild_index_batch_size": int & >=4096 & <=16777216 | *1048576

    // Maximum number of edges returned per vertex during traversal.
    // Extra edges will be truncated if exceed this limit.
    // This prevents performance degradation or OOM caused by dense vertices.
    "--max_edge_returned_per_vertex": int & >=1 & <=2147483647 | *2147483647

    // Minimum reserved bytes of data path
    "--minimum_reserved_bytes": int & >=0 | *268435456

    "--ng_black_box_switch": bool | *true
    "--ng_black_box_home": string | *"black_box"
    "--ng_black_box_dump_period_seconds": int & >=0 | *5
    "--ng_black_box_file_lifetime_seconds": int & >=0 | *1800

    // Memory tracker limit ratio or mode.
    // Valid values:
    //   (0, 1]: threshold-based static percentage of available memory.
    //           Query will fail if it causes OOM beyond this threshold.
    //   2:      Dynamic self-adaptive mode. Experimental.
    //   3:      Disabled. Only records memory usage without enforcement.
    //
    // Warning: This setting only takes effect if system_memory_high_watermark_ratio ≠ 1.
    //             For mixed deployments, adjust according to expected memory allocation.
    "--memory_tracker_limit_ratio": number & >0 & <=1 | 2 | 3 | *0.8

    // Reserved memory size in MB for system usage (not tracked by memory tracker).
    "--memory_tracker_untracked_reserved_memory_mb": int & >=0 & <=102400 | *50

    // Whether to generate detailed memory tracking logs periodically.
    "--memory_tracker_detail_log": bool | *false

    // Interval in milliseconds for generating memory tracking logs.
    // Only takes effect when memory_tracker_detail_log is true.
    "--memory_tracker_detail_log_interval_ms": int & >=1000 & <=3600000 | *60000

    // Whether to enable periodic memory purging.
    "--memory_purge_enabled": bool | *true

    // Interval in seconds for memory purging.
    // Only takes effect when memory_purge_enabled is true.
    "--memory_purge_interval_seconds": int & >=1 & <=86400 | *10

    "--enable_negative_pool": bool | *false

    // Negative pool size in MB
    "--negative_pool_capacity": int | *50

    // TTL in seconds for negative items in the cache
    "--negative_item_ttl": int | *300


    // Whether to enable storage cache
    "--enable_storage_cache": bool | *false

    // Total capacity reserved for storage in memory cache in MB
    "--storage_cache_capacity": int | *0

    // Estimated number of cache entries on this storage node in base 2 logarithm. E.g., in case of 20, the estimated number of entries will be 2^20.
    // A good estimate can be log2(#vertices on this storage node). The maximum allowed is 31.
    "--storage_cache_entries_power": int | *20

    // Whether to add vertex pool in cache. Only valid when storage cache is enabled.
    "--enable_vertex_pool": bool | *false

    // Vertex pool size in MB
    "--vertex_pool_capacity": int | *50

    // TTL in seconds for vertex items in the cache
    "--vertex_item_ttl": int | *300

    // Cache file location
    "--nv_cache_path": string | *"/tmp/cache"

    // Cache file size in MB
    "--nv_cache_size": int | *0

    // DRAM part size of non-volatile cache in MB
    "--nv_dram_size": int | *50

    // DRAM part bucket power. The value is a logarithm with a base of 2. Optional values are 0-32.
    "--nv_bucket_power": int | *20

    // DRAM part lock power. The value is a logarithm with a base of 2. The recommended value is max(1, nv_bucket_power - 10).
    "--nv_lock_power": int | *10

    // whether send raft snapshot by files via http
    "--snapshot_send_files": bool | *true

    "--containerized": bool | *false

}

configuration: #NebulaStoragedParameter & {

}
