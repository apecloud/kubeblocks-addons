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

#MysqlParameter: {
	// This variable is available only if the authentication_windows Windows authentication plugin is enabled and debugging code is enabled.
	authentication_windows_log_level?: int & >= 0 & <= 4 | *2

	// This variable is available only if the authentication_windows Windows authentication plugin is enabled.
	authentication_windows_use_principal_name?: bool & true | false | *true

	// This variable is available if the server was compiled using OpenSSL (see Section 6.3.4, “SSL Library-Dependent Capabilities”).
	auto_generate_certs?: bool & true | false | *true

	// auto_increment_increment and auto_increment_offset are intended for use with source-to-source replication, and can be used to control the operation of AUTO_INCREMENT columns.
	auto_increment_increment?: int & >= 1 & <= 65535 | *1

	// This variable has a default value of 1.
	auto_increment_offset?: int & >= 1 & <= 65535 | *1

	// The autocommit mode.
	autocommit?: bool & true | false | *true

	// When this variable has a value of 1 (the default), the server automatically grants the EXECUTE and ALTER ROUTINE privileges to the creator of a stored routine, if the user cannot already execute and alter or drop the routine.
	automatic_sp_privileges?: bool & true | false | *true

	// The number of outstanding connection requests MySQL can have.
	back_log?: int & >= 1 & <= 65535

	// The path to the MySQL installation base directory.big_tables
	basedir?: string | *"configuration-dependent default"

	// If enabled, the server stores all temporary tables on disk rather than in memory.
	big_tables?: bool & true | false | *false

	// The MySQL server listens on a single network socket for TCP/IP connections.
	bind_address?: string | *"*"

	// The size of the cache to hold changes to the binary log during a transaction.A binary log cache is allocated for each client if the server supports any transactional storage engines and if the server has the binary log enabled (--log-bin option).
	binlog_cache_size?: int & >= 4096 & <= 18446744073709547520 | *32768

	// NONECRC32When enabled, this variable causes the source to write a checksum for each event in the binary log.
	binlog_checksum?: string | *"CRC32"

	// Due to concurrency issues, a replica can become inconsistent when a transaction contains updates to both transactional and nontransactional tables.
	binlog_direct_non_transactional_updates?: bool & true | false | *false

	// IGNORE_ERRORABORT_SERVERControls what happens when the server encounters an error such as not being able to write to, flush or synchronize the binary log, which can cause the source's binary log to become inconsistent and replicas to lose synchronization.In MySQL 5.7.7 and higher, this variable defaults to ABORT_SERVER, which makes the server halt logging and shut down whenever it encounters such an error with the binary log.
	binlog_error_action?: string & "IGNORE_ERROR" | "ABORT_SERVER" | *"ABORT_SERVER"

	// MIXEDSTATEMENTROWThis system variable sets the binary logging format, and can be any one of STATEMENT, ROW, or MIXED.
	binlog_format?: string & "MIXED" | "STATEMENT" | "ROW" | *"ROW"

	// Controls how many microseconds the binary log commit waits before synchronizing the binary log file to disk.
	binlog_group_commit_sync_delay?: int & >= 0 & <= 1000000 | *0

	// The maximum number of transactions to wait for before aborting the current delay as specified by binlog_group_commit_sync_delay.
	binlog_group_commit_sync_no_delay_count?: int & >= 0 & <= 100000 | *0

	// When this variable is enabled on a replication source server (which is the default), transaction commit instructions issued to storage engines are serialized on a single thread, so that transactions are always committed in the same order as they are written to the binary log.
	binlog_order_commits?: bool & true | false | *true

	// full (Log all columns)minimal (Log only changed columns, and columns needed to identify rows)noblob (Log all columns, except for unneeded BLOB and TEXT columns)For MySQL row-based replication, this variable determines how row images are written to the binary log.In MySQL row-based replication, each row change event contains two images, a “before” image whose columns are matched against when searching for the row to be updated, and an “after” image containing the changes.
	binlog_row_image?: string & "full " | "minimal " | "noblob " | *"full"

	// This system variable affects row-based logging only.
	binlog_rows_query_log_events?: bool & true | false | *false

	// This variable determines the size of the cache for the binary log to hold nontransactional statements issued during a transaction.Separate binary log transaction and statement caches are allocated for each client if the server supports any transactional storage engines and if the server has the binary log enabled (--log-bin option).
	binlog_stmt_cache_size?: int & >= 4096 & <= 18446744073709547520 | *32768

	// This variable controls the block encryption mode for block-based algorithms such as AES.
	block_encryption_mode?: string | *"aes-128-ecb"

	// MyISAM uses a special tree-like cache to make bulk inserts faster for INSERT ...
	bulk_insert_buffer_size?: int & >= 0 & <= 18446744073709551615 | *8388608

	// The character set for statements that arrive from the client.
	character_set_client?: string | *"utf8"

	// The character set used for literals specified without a character set introducer and for number-to-string conversion.
	character_set_connection?: string | *"utf8"

	// The character set used by the default database.
	character_set_database?: string | *"latin1"

	// The file system character set.
	character_set_filesystem?: string | *"binary"

	// The character set used for returning query results to the client.
	character_set_results?: string | *"utf8"

	// The servers default character set.
	character_set_server?: string | *"latin1"

	// The character set used by the server for storing identifiers.
	character_set_system?: string | *"utf8"

	// The directory where character sets are installed.
	character_sets_dir?: string

	// Some authentication plugins implement proxy user mapping for themselves (for example, the PAM and Windows authentication plugins).
	check_proxy_users?: bool & true | false | *false

	// The collation of the connection character set.
	collation_connection?: string

	// The collation used by the default database.
	collation_database?: string | *"latin1_swedish_ci"

	// The server's default collation.
	collation_server?: string | *"latin1_swedish_ci"

	// NO_CHAINCHAINRELEASE012The transaction completion type.
	completion_type?: string & "NO_CHAIN" | "CHAIN" | "RELEASE" | *"NO_CHAIN"

	// NEVERAUTOALWAYS012If AUTO (the default), MySQL permits INSERT and SELECT statements to run concurrently for MyISAM tables that have no free blocks in the middle of the data file.This variable can take the values shown in the following table.
	concurrent_insert?: string & "NEVER" | "AUTO" | "ALWAYS" | *"AUTO"

	// The number of seconds that the mysqld server waits for a connect packet before responding with Bad handshake.
	connect_timeout?: int & >= 2 & <= 31536000 | *10

	// Whether to write a core file if the server unexpectedly exits.
	core_file?: bool & true | false | *false

	// Enable this option on the source server to use the InnoDB memcached plugin (daemon_memcached) with the MySQL binary log.
	daemon_memcached_enable_binlog?: bool & true | false | *false

	// Specifies the shared library that implements the InnoDB memcached plugin.For more information, see Section 14.21.3, “Setting Up the InnoDB memcached Plugin”.daemon_memcached_engine_lib_path
	daemon_memcached_engine_lib_name?: string | *"innodb_engine.so"

	// The path of the directory containing the shared library that implements the InnoDBmemcached plugin.
	daemon_memcached_engine_lib_path?: string | *"NULL"

	// Used to pass space-separated memcached options to the underlying memcached memory object caching daemon on startup.
	daemon_memcached_option?: string

	// Specifies how many memcached read operations (get operations) to perform before doing a COMMIT to start a new transaction.
	daemon_memcached_r_batch_size?: int & >= 1 & <= 1073741824 | *1

	// Specifies how many memcached write operations, such as add, set, and incr, to perform before doing a COMMIT to start a new transaction.
	daemon_memcached_w_batch_size?: int & >= 1 & <= 1048576 | *1

	// The path to the MySQL server data directory.
	datadir?: string

	// This variable is the user interface to the Debug Sync facility.
	debug_sync?: string

	// mysql_native_passwordsha256_passwordThe default authentication plugin.
	default_authentication_plugin?: string & "mysql_native_password" | "sha256_password" | *"mysql_native_password"

	// The default storage engine for tables.
	default_storage_engine?: string | *"InnoDB"

	// The default storage engine for TEMPORARY tables (created with CREATE TEMPORARY TABLE).
	default_tmp_storage_engine?: string | *"InnoDB"

	// The default mode value to use for the WEEK() function.
	default_week_format?: int & >= 0 & <= 7 | *0

	// OFFONALLThis variable specifies how to use delayed key writes.
	delay_key_write?: string & "OFF" | "ON" | "ALL" | *"ON"

	// This variable indicates which storage engines cannot be used to create tables or tablespaces.
	disabled_storage_engines?: string | *"empty string"

	// This variable controls how the server handles clients with expired passwords:If the client indicates that it can handle expired passwords, the value of disconnect_on_expired_password is irrelevant.
	disconnect_on_expired_password?: bool & true | false | *true

	// This variable indicates the number of digits by which to increase the scale of the result of division operations performed with the / operator.
	div_precision_increment?: int & >= 0 & <= 30 | *4

	// Whether optimizer JSON output should add end markers.
	end_markers_in_json?: bool & true | false | *false

	// This variable indicates the number of equality ranges in an equality comparison condition when the optimizer should switch from using index dives to index statistics in estimating the number of qualifying rows.
	eq_range_index_dive_limit?: int & >= 0 & <= 4294967295 | *200

	// OFFONDISABLEDThis variable enables or disables, and starts or stops, the Event Scheduler.
	event_scheduler?: string & "OFF" | "ON" | "DISABLED" | *"OFF"

	// The number of days for automatic binary log file removal.
	expire_logs_days?: int & >= 0 & <= 99 | *0

	// The external user name used during the authentication process, as set by the plugin used to authenticate the client.
	external_user?: string

	// If ON, the server flushes (synchronizes) all changes to disk after each SQL statement.
	flush?: bool & true | false | *false

	// If this is set to a nonzero value, all tables are closed every flush_time seconds to free up resources and synchronize unflushed data to disk.
	flush_time?: int & >= 0 & <= 31536000 | *0

	// If set to 1 (the default), foreign key constraints are checked.
	foreign_key_checks?: bool & true | false | *true

	// The list of operators supported by boolean full-text searches performed using IN BOOLEAN MODE.
	ft_boolean_syntax?: ft_boolean_syntax?: string | *'+ -><()~*:""&|'

	// The maximum length of the word to be included in a MyISAM FULLTEXT index.FULLTEXT indexes on MyISAM tables must be rebuilt after changing this variable.
	ft_max_word_len?: int & >= 10 & <= 84 | *84

	// The minimum length of the word to be included in a MyISAM FULLTEXT index.FULLTEXT indexes on MyISAM tables must be rebuilt after changing this variable.
	ft_min_word_len?: int & >= 1 & <= 82 | *4

	// The number of top matches to use for full-text searches performed using WITH QUERY EXPANSION.ft_stopword_file
	ft_query_expansion_limit?: int & >= 0 & <= 1000 | *20

	// The file from which to read the list of stopwords for full-text searches on MyISAM tables.
	ft_stopword_file?: string

	// Whether the general query log is enabled.
	general_log?: bool & true | false | *false

	// The name of the general query log file.
	general_log_file?: string | *"host_name.log"

	// The maximum permitted result length in bytes for the GROUP_CONCAT() function.
	group_concat_max_len?: int & >= 4 & <= 18446744073709551615 | *1024

	// YES (SSL support available)DISABLED (SSL support was compiled into server, but server was not started with necessary options to enable it)YES if mysqld supports SSL connections, DISABLED if the server was compiled with SSL support, but was not started with the appropriate connection-encryption options.
	have_ssl?: string

	// Whether the statement execution timeout feature is available (see Statement Execution Time Optimizer Hints).
	have_statement_timeout?: bool & true | false

	// The MySQL server maintains an in-memory host cache that contains client host name and IP address information and is used to avoid Domain Name System (DNS) lookups; see Section 5.1.11.2, “DNS Lookups and the Host Cache”.The host_cache_size variable controls the size of the host cache, as well as the size of the Performance Schema host_cache table that exposes the cache contents.
	host_cache_size?: int & >= 0 & <= 65536

	// The server sets this variable to the server host name at startup.identityThis variable is a synonym for the last_insert_id variable.
	hostname?: string

	// A string to be executed by the server for each client that connects.
	init_connect?: string

	// If specified, this variable names a file containing SQL statements to be read and executed during the startup process.
	init_file?: string

	// Specifies whether to dynamically adjust the rate of flushing dirty pages in the InnoDBbuffer pool based on the workload.
	innodb_adaptive_flushing?: bool & true | false | *true

	// Defines the low water mark representing percentage of redo log capacity at which adaptive flushing is enabled.
	innodb_adaptive_flushing_lwm?: int & >= 0 & <= 70 | *10

	// Whether the InnoDBadaptive hash index is enabled or disabled.
	innodb_adaptive_hash_index?: bool & true | false | *true

	// Partitions the adaptive hash index search system.
	innodb_adaptive_hash_index_parts?: int & >= 1 & <= 512 | *8

	// Permits InnoDB to automatically adjust the value of innodb_thread_sleep_delay up or down according to the current workload.
	innodb_adaptive_max_sleep_delay?: int & >= 0 & <= 1000000 | *150000

	// How often to auto-commit idle connections that use the InnoDB memcached interface, in seconds.
	innodb_api_bk_commit_interval?: int & >= 1 & <= 1073741824 | *5

	// Use this option to disable row locks when InnoDB memcached performs DML operations.
	innodb_api_disable_rowlock?: bool & true | false | *false

	// Lets you use the InnoDBmemcached plugin with the MySQL binary log.
	innodb_api_enable_binlog?: bool & true | false | *false

	// Locks the table used by the InnoDBmemcached plugin, so that it cannot be dropped or altered by DDL through the SQL interface.
	innodb_api_enable_mdl?: bool & true | false | *false

	// Controls the transaction isolation level on queries processed by the memcached interface.
	innodb_api_trx_level?: int & >= 0 & <= 3 | *0

	// The increment size (in megabytes) for extending the size of an auto-extending InnoDBsystem tablespace file when it becomes full.
	innodb_autoextend_increment?: int & >= 1 & <= 1000 | *64

	// 012The lock mode to use for generating auto-increment values.
	innodb_autoinc_lock_mode?: int | *1

	// innodb_buffer_pool_chunk_size defines the chunk size for InnoDB buffer pool resizing operations.To avoid copying all buffer pool pages during resizing operations, the operation is performed in “chunks”.
	innodb_buffer_pool_chunk_size?: int | *134217728

	// Specifies whether to record the pages cached in the InnoDBbuffer pool when the MySQL server is shut down, to shorten the warmup process at the next restart.
	innodb_buffer_pool_dump_at_shutdown?: bool & true | false | *true

	// Immediately makes a record of pages cached in the InnoDBbuffer pool.
	innodb_buffer_pool_dump_now?: bool & true | false | *false

	// Specifies the percentage of the most recently used pages for each buffer pool to read out and dump.
	innodb_buffer_pool_dump_pct?: int & >= 1 & <= 100 | *25

	// Specifies the name of the file that holds the list of tablespace IDs and page IDs produced by innodb_buffer_pool_dump_at_shutdown or innodb_buffer_pool_dump_now.
	innodb_buffer_pool_filename?: string | *"ib_buffer_pool"

	// The number of regions that the InnoDBbuffer pool is divided into.
	innodb_buffer_pool_instances?: int & >= 1 & <= 64

	// Interrupts the process of restoring InnoDBbuffer pool contents triggered by innodb_buffer_pool_load_at_startup or innodb_buffer_pool_load_now.Enabling innodb_buffer_pool_load_abort triggers the abort action but does not alter the variable setting, which always remains OFF or 0.
	innodb_buffer_pool_load_abort?: bool & true | false | *false

	// Specifies that, on MySQL server startup, the InnoDBbuffer pool is automatically warmed up by loading the same pages it held at an earlier time.
	innodb_buffer_pool_load_at_startup?: bool & true | false | *true

	// Immediately warms up the InnoDBbuffer pool by loading data pages without waiting for a server restart.
	innodb_buffer_pool_load_now?: bool & true | false | *false

	// The size in bytes of the buffer pool, the memory area where InnoDB caches table and index data.
	innodb_buffer_pool_size?: int & >=5242880 & <=18446744073709551615 @k8sResource(quantity)

	// Maximum size for the InnoDBchange buffer, as a percentage of the total size of the buffer pool.
	innodb_change_buffer_max_size?: int & >= 0 & <= 50 | *25

	// noneinsertsdeleteschangespurgesallWhether InnoDB performs change buffering, an optimization that delays write operations to secondary indexes so that the I/O operations can be performed sequentially.
	innodb_change_buffering?: string & "none" | "inserts" | "deletes" | "changes" | "purges" | "all" | *"all"

	// Sets a debug flag for InnoDB change buffering.
	innodb_change_buffering_debug?: int & >= 0 & <= 2 | *0

	// crc32strict_crc32innodbstrict_innodbnonestrict_noneSpecifies how to generate and verify the checksum stored in the disk blocks of InnoDBtablespaces.
	innodb_checksum_algorithm?: string & "crc32" | "strict_crc32" | "innodb" | "strict_innodb" | "none" | "strict_none" | *"crc32"

	// Enables per-index compression-related statistics in the Information Schema INNODB_CMP_PER_INDEX table.
	innodb_cmp_per_index_enabled?: bool & true | false | *false

	// The number of threads that can commit at the same time.
	innodb_commit_concurrency?: int & >= 0 & <= 1000 | *0

	// nonezliblz4lz4hcCompresses all tables using a specified compression algorithm without having to define a COMPRESSION attribute for each table.
	innodb_compress_debug?: string & "none" | "zlib" | "lz4" | "lz4hc" | *"none"

	// Defines the compression failure rate threshold for a table, as a percentage, at which point MySQL begins adding padding within compressed pages to avoid expensive compression failures.
	innodb_compression_failure_threshold_pct?: int & >= 0 & <= 100 | *5

	// Specifies the level of zlib compression to use for InnoDBcompressed tables and indexes.
	innodb_compression_level?: int & >= 0 & <= 9 | *6

	// Specifies the maximum percentage that can be reserved as free space within each compressed page, allowing room to reorganize the data and modification log within the page when a compressed table or index is updated and the data might be recompressed.
	innodb_compression_pad_pct_max?: int & >= 0 & <= 75 | *50

	// Determines the number of threads that can enter InnoDB concurrently.
	innodb_concurrency_tickets?: int & >= 1 & <= 4294967295 | *5000

	// Defines the name, size, and attributes of InnoDB system tablespace data files..
	innodb_data_file_path?: string | *"ibdata1:12M:autoextend"

	// The common part of the directory path for InnoDBsystem tablespace data files.
	innodb_data_home_dir?: string

	// REDUNDANTCOMPACTDYNAMICThe innodb_default_row_format option defines the default row format for InnoDB tables and user-created temporary tables.
	innodb_default_row_format?: string & "REDUNDANT" | "COMPACT" | "DYNAMIC" | *"DYNAMIC"

	// Disables resizing of the InnoDB buffer pool.
	innodb_disable_resize_buffer_pool_debug?: bool & true | false | *true

	// Disables the operating system file system cache for merge-sort temporary files.
	innodb_disable_sort_file_cache?: bool & true | false | *false

	// When enabled (the default), InnoDB stores all data twice, first to the doublewrite buffer, then to the actual data files.
	innodb_doublewrite?: bool & true | false | *true

	// 012The InnoDBshutdown mode.
	innodb_fast_shutdown?: int | *1

	// By default, setting innodb_fil_make_page_dirty_debug to the ID of a tablespace immediately dirties the first page of the tablespace.
	innodb_fil_make_page_dirty_debug?: int | *0

	// When innodb_file_per_table is enabled, tables are created in file-per-table tablespaces by default.
	innodb_file_per_table?: bool & true | false | *true

	// InnoDB performs a bulk load when creating or rebuilding indexes.
	innodb_fill_factor?: int & >= 10 & <= 100 | *100

	// Write and flush the logs every N seconds.
	innodb_flush_log_at_timeout?: int & >= 1 & <= 2700 | *1

	// 012Controls the balance between strict ACID compliance for commit operations and higher performance that is possible when commit-related I/O operations are rearranged and done in batches.
	innodb_flush_log_at_trx_commit?: string | *"1"

	// fsyncO_DSYNClittlesyncnosyncO_DIRECTO_DIRECT_NO_FSYNCasync_unbufferednormalunbufferedDefines the method used to flush data to InnoDB data files and log files, which can affect I/O throughput.If innodb_flush_method is set to NULL on a Unix-like system, the fsync option is used by default.
	innodb_flush_method?: string | *"NULL"

	// 012Specifies whether flushing a page from the InnoDBbuffer pool also flushes other dirty pages in the same extent.A setting of 0 disables innodb_flush_neighbors.
	innodb_flush_neighbors?: string | *"1"

	// The innodb_flush_sync variable, which is enabled by default, causes the innodb_io_capacity setting to be ignored during bursts of I/O activity that occur at checkpoints.
	innodb_flush_sync?: bool & true | false | *true

	// Number of iterations for which InnoDB keeps the previously calculated snapshot of the flushing state, controlling how quickly adaptive flushing responds to changing workloads.
	innodb_flushing_avg_loops?: int & >= 1 & <= 1000 | *30

	// Permits InnoDB to load tables at startup that are marked as corrupted.
	innodb_force_load_corrupted?: bool & true | false | *false

	// The crash recovery mode, typically only changed in serious troubleshooting situations.
	innodb_force_recovery?: int & >= 0 & <= 6 | *0

	// Specifies the qualified name of an InnoDB table containing a FULLTEXT index.
	innodb_ft_aux_table?: string

	// The memory allocated, in bytes, for the InnoDB FULLTEXT search index cache, which holds a parsed document in memory while creating an InnoDBFULLTEXT index.
	innodb_ft_cache_size?: int & >= 1600000 & <= 80000000 | *8000000

	// Whether to enable additional full-text search (FTS) diagnostic output.
	innodb_ft_enable_diag_print?: bool & true | false | *false

	// Specifies that a set of stopwords is associated with an InnoDB FULLTEXT index at the time the index is created.
	innodb_ft_enable_stopword?: bool & true | false | *true

	// Maximum character length of words that are stored in an InnoDB FULLTEXT index.
	innodb_ft_max_token_size?: int & >= 10 & <= 84 | *84

	// Minimum length of words that are stored in an InnoDB FULLTEXT index.
	innodb_ft_min_token_size?: int & >= 0 & <= 16 | *3

	// Number of words to process during each OPTIMIZE TABLE operation on an InnoDB FULLTEXT index.
	innodb_ft_num_word_optimize?: int & >= 1000 & <= 10000 | *2000

	// The InnoDB full-text search query result cache limit (defined in bytes) per full-text search query or per thread.
	innodb_ft_result_cache_limit?: int | *2000000000

	// This option is used to specify your own InnoDB FULLTEXT index stopword list for all InnoDB tables.
	innodb_ft_server_stopword_table?: string | *"NULL"

	// Number of threads used in parallel to index and tokenize text in an InnoDB FULLTEXT index when building a search index.For related information, see Section 14.6.2.4, “InnoDB Full-Text Indexes”, and innodb_sort_buffer_size.innodb_ft_total_cache_size
	innodb_ft_sort_pll_degree?: int & >= 1 & <= 16 | *2

	// The total memory allocated, in bytes, for the InnoDB full-text search index cache for all tables.
	innodb_ft_total_cache_size?: int & >= 32000000 & <= 1600000000 | *640000000

	// This option is used to specify your own InnoDB FULLTEXT index stopword list on a specific table.
	innodb_ft_user_stopword_table?: string | *"NULL"

	// The innodb_io_capacity variable defines the number of I/O operations per second (IOPS) available to InnoDB background tasks, such as flushing pages from the buffer pool and merging data from the change buffer.For information about configuring the innodb_io_capacity variable, see Section 14.8.8, “Configuring InnoDB I/O Capacity”.innodb_io_capacity_max
	innodb_io_capacity?: int | *200

	// If flushing activity falls behind, InnoDB can flush more aggressively, at a higher rate of I/O operations per second (IOPS) than defined by the innodb_io_capacity variable.
	innodb_io_capacity_max?: int

	// Limits the number of records per B-tree page.
	innodb_limit_optimistic_insert_debug?: int | *0

	// The length of time in seconds an InnoDBtransaction waits for a row lock before giving up.
	innodb_lock_wait_timeout?: int & >= 1 & <= 1073741824 | *50

	// The size in bytes of the buffer that InnoDB uses to write to the log files on disk.
	innodb_log_buffer_size?: int & >= 1048576 & <= 4294967295 | *16777216

	// Enable this debug option to force InnoDB to write a checkpoint.
	innodb_log_checkpoint_now?: bool & true | false | *false

	// Enables or disables checksums for redo log pages.innodb_log_checksums=ON enables the CRC-32C checksum algorithm for redo log pages.
	innodb_log_checksums?: bool & true | false | *true

	// Specifies whether images of re-compressedpages are written to the redo log.
	innodb_log_compressed_pages?: bool & true | false | *true

	// The size in bytes of each log file in a log group.
	innodb_log_file_size?: int | *50331648

	// The number of log files in the log group.
	innodb_log_files_in_group?: int & >= 2 & <= 100 | *2

	// The directory path to the InnoDBredo log files, whose number is specified by innodb_log_files_in_group.
	innodb_log_group_home_dir?: string

	// Defines the write-ahead block size for the redo log, in bytes.
	innodb_log_write_ahead_size?: int | *8192

	// A parameter that influences the algorithms and heuristics for the flush operation for the InnoDBbuffer pool.
	innodb_lru_scan_depth?: int | *1024

	// InnoDB tries to flush data from the buffer pool so that the percentage of dirty pages does not exceed this value.
	innodb_max_dirty_pages_pct?: int | *75

	// Defines a low water mark representing the percentage of dirty pages at which preflushing is enabled to control the dirty page ratio.
	innodb_max_dirty_pages_pct_lwm?: int | *0

	// Defines the desired maximum purge lag.
	innodb_max_purge_lag?: int & >= 0 & <= 4294967295 | *0

	// Specifies the maximum delay in microseconds for the delay imposed when the innodb_max_purge_lag threshold is exceeded.
	innodb_max_purge_lag_delay?: int & >= 0 & <= 10000000 | *0

	// Defines a threshold size for undo tablespaces.
	innodb_max_undo_log_size?: int | *1073741824

	// Defines a page-full percentage value for index pages that overrides the current MERGE_THRESHOLD setting for all indexes that are currently in the dictionary cache.
	innodb_merge_threshold_set_all_debug?: int & >= 1 & <= 50 | *50

	// This variable acts as a switch, disabling InnoDBmetrics counters.
	innodb_monitor_disable?: string

	// This variable acts as a switch, enabling InnoDBmetrics counters.
	innodb_monitor_enable?: string

	// countermodulepatternallThis variable acts as a switch, resetting the count value for InnoDBmetrics counters to zero.
	innodb_monitor_reset?: string & "counter" | "module" | "pattern" | "all" | *"NULL"

	// countermodulepatternallThis variable acts as a switch, resetting all values (minimum, maximum, and so on) for InnoDBmetrics counters.
	innodb_monitor_reset_all?: string & "counter" | "module" | "pattern" | "all" | *"NULL"

	// Enables the NUMA interleave memory policy for allocation of the InnoDB buffer pool.
	innodb_numa_interleave?: bool & true | false | *false

	// Specifies the approximate percentage of the InnoDBbuffer pool used for the old block sublist.
	innodb_old_blocks_pct?: int & >= 5 & <= 95 | *37

	// Non-zero values protect against the buffer pool being filled by data that is referenced only for a brief period, such as during a full table scan.
	innodb_old_blocks_time?: int | *1000

	// Specifies an upper limit in bytes on the size of the temporary log files used during online DDL operations for InnoDB tables.
	innodb_online_alter_log_max_size?: int | *134217728

	// Specifies the maximum number of files that InnoDB can have open at one time.
	innodb_open_files?: int & >= 10 & <= 2147483647

	// Changes the way OPTIMIZE TABLE operates on InnoDB tables.
	innodb_optimize_fulltext_only?: bool & true | false | *false

	// The number of page cleaner threads that flush dirty pages from buffer pool instances.
	innodb_page_cleaners?: int & >= 1 & <= 64 | *4

	// 40968192163843276865536Specifies the page size for InnoDBtablespaces.
	innodb_page_size?: string | *"16384"

	// When this option is enabled, information about all deadlocks in InnoDB user transactions is recorded in the mysqld error log.
	innodb_print_all_deadlocks?: bool & true | false | *false

	// Defines the number of undo log pages that purge parses and processes in one batch from the history list.
	innodb_purge_batch_size?: int & >= 1 & <= 5000 | *300

	// Defines the frequency with which the purge system frees rollback segments in terms of the number of times that purge is invoked.
	innodb_purge_rseg_truncate_frequency?: int & >= 1 & <= 128 | *128

	// The number of background threads devoted to the InnoDBpurge operation.
	innodb_purge_threads?: int & >= 1 & <= 32 | *4

	// Enables the random read-ahead technique for optimizing InnoDB I/O.For details about performance considerations for different types of read-ahead requests, see Section 14.8.3.4, “Configuring InnoDB Buffer Pool Prefetching (Read-Ahead)”.
	innodb_random_read_ahead?: bool & true | false | *false

	// Controls the sensitivity of linear read-ahead that InnoDB uses to prefetch pages into the buffer pool.
	innodb_read_ahead_threshold?: int & >= 0 & <= 64 | *56

	// The number of I/O threads for read operations in InnoDB.
	innodb_read_io_threads?: int & >= 1 & <= 64 | *4

	// Starts InnoDB in read-only mode.
	innodb_read_only?: bool & true | false | *false

	// The replication thread delay in milliseconds on a replica server if innodb_thread_concurrency is reached.innodb_rollback_on_timeout
	innodb_replication_delay?: int & >= 0 & <= 4294967295 | *0

	// InnoDB rolls back only the last statement on a transaction timeout by default.
	innodb_rollback_on_timeout?: bool & true | false | *false

	// Defines the number of rollback segments used by InnoDB for transactions that generate undo records.
	innodb_rollback_segments?: int & >= 1 & <= 128 | *128

	// Saves a page number.
	innodb_saved_page_number_debug?: int | *0

	// This variable defines:The sort buffer size for online DDL operations that create or rebuild secondary indexes.The amount by which the temporary log file is extended when recording concurrent DML during an online DDL operation, and the size of the temporary log file read buffer and write buffer.For related information, see Section 14.13.3, “Online DDL Space Requirements”.innodb_spin_wait_delay
	innodb_sort_buffer_size?: int & >= 65536 & <= 67108864 | *1048576

	// The maximum delay between polls for a spin lock.
	innodb_spin_wait_delay?: int | *6

	// Causes InnoDB to automatically recalculate persistent statistics after the data in a table is changed substantially.
	innodb_stats_auto_recalc?: bool & true | false | *true

	// nulls_equalnulls_unequalnulls_ignoredHow the server treats NULL values when collecting statistics about the distribution of index values for InnoDB tables.
	innodb_stats_method?: string & "nulls_equal" | "nulls_unequal" | "nulls_ignored" | *"nulls_equal"

	// This option only applies when optimizer statistics are configured to be non-persistent.
	innodb_stats_on_metadata?: bool & true | false | *false

	// Specifies whether InnoDB index statistics are persisted to disk.
	innodb_stats_persistent?: bool & true | false | *true

	// The number of index pages to sample when estimating cardinality and other statistics for an indexed column, such as those calculated by ANALYZE TABLE.
	innodb_stats_persistent_sample_pages?: int & >= 1 & <= 18446744073709551615 | *20

	// The number of index pages to sample when estimating cardinality and other statistics for an indexed column, such as those calculated by ANALYZE TABLE.
	innodb_stats_transient_sample_pages?: int & >= 1 & <= 18446744073709551615 | *8

	// Enables or disables periodic output for the standard InnoDB Monitor.
	innodb_status_output?: bool & true | false | *false

	// Enables or disables the InnoDB Lock Monitor.
	innodb_status_output_locks?: bool & true | false | *false

	// When innodb_strict_mode is enabled, InnoDB returns errors rather than warnings when checking for invalid or incompatible table options.It checks that KEY_BLOCK_SIZE, ROW_FORMAT, DATA DIRECTORY, TEMPORARY, and TABLESPACE options are compatible with each other and other settings.innodb_strict_mode=ON also enables a row size check when creating or altering a table, to prevent INSERT or UPDATE from failing due to the record being too large for the selected page size.You can enable or disable innodb_strict_mode on the command line when starting mysqld, or in a MySQL configuration file.
	innodb_strict_mode?: bool & true | false | *true

	// Defines the size of the mutex/lock wait array.
	innodb_sync_array_size?: int & >= 1 & <= 1024 | *1

	// Enables sync debug checking for the InnoDB storage engine.
	innodb_sync_debug?: bool & true | false | *false

	// The number of times a thread waits for an InnoDB mutex to be freed before the thread is suspended.innodb_sync_debug
	innodb_sync_spin_loops?: int & >= 0 & <= 4294967295 | *30

	// If autocommit = 0, InnoDB honors LOCK TABLES; MySQL does not return from LOCK TABLES ...
	innodb_table_locks?: bool & true | false | *true

	// Defines the relative path, name, size, and attributes of InnoDBtemporary tablespace data files.
	innodb_temp_data_file_path?: string | *"ibtmp1:12M:autoextend"

	// Defines the maximum number of threads permitted inside of InnoDB.
	innodb_thread_concurrency?: int & >= 0 & <= 1000 | *0

	// Defines how long InnoDB threads sleep before joining the InnoDB queue, in microseconds.
	innodb_thread_sleep_delay?: int & >= 0 & <= 1000000 | *10000

	// Pauses purging of delete-marked records while allowing the purge view to be updated.
	innodb_trx_purge_view_update_only_debug?: bool & true | false | *false

	// Sets a debug flag that limits TRX_RSEG_N_SLOTS to a given value for the trx_rsegf_undo_find_free function that looks for free slots for undo log segments.
	innodb_trx_rseg_n_slots_debug?: int & >= 0 & <= 1024 | *0

	// The path where InnoDB creates undo tablespaces.
	innodb_undo_directory?: string

	// When enabled, undo tablespaces that exceed the threshold value defined by innodb_max_undo_log_size are marked for truncation.
	innodb_undo_log_truncate?: bool & true | false | *false

	// Specifies whether to use the Linux asynchronous I/O subsystem.
	innodb_use_native_aio?: bool & true | false | *true

	// The number of I/O threads for write operations in InnoDB.
	innodb_write_io_threads?: int & >= 1 & <= 64 | *4

	// The number of seconds the server waits for activity on an interactive connection before closing it.
	interactive_timeout?: int & >= 1 & <= 31536000 | *28800

	// MYISAMINNODBThe storage engine for on-disk internal temporary tables (see Section 8.4.4, “Internal Temporary Table Use in MySQL”).
	internal_tmp_disk_storage_engine?: string & "MYISAM" | "INNODB" | *"INNODB"

	// If a MyISAM table is created with no DATA DIRECTORY option, the .MYD file is created in the database directory.
	keep_files_on_create?: bool & true | false | *false

	// Index blocks for MyISAM tables are buffered and are shared by all threads.
	key_buffer_size?: int | *8388608

	// This value controls the demotion of buffers from the hot sublist of a key cache to the warm sublist.
	key_cache_age_threshold?: int & >= 100 & <= 18446744073709551516 | *300

	// The size in bytes of blocks in the key cache.
	key_cache_block_size?: int & >= 512 & <= 16384 | *1024

	// The division point between the hot and warm sublists of the key cache buffer list.
	key_cache_division_limit?: int & >= 1 & <= 100 | *100

	// Whether mysqld was compiled with options for large file support.large_pages
	large_files_support?: bool & true | false

	// If large page support is enabled, this shows the size of memory pages.
	large_page_size?: int & >= 0 & <= 65535 | *0

	// The locale to use for error messages.
	lc_messages?: string | *"en_US"

	// The directory where error messages are located.
	lc_messages_dir?: string

	// This variable specifies the locale that controls the language used to display day and month names and abbreviations.
	lc_time_names?: string

	// The type of license the server has.local_infile
	license?: string | *"GPL"

	// This variable controls server-side LOCAL capability for LOAD DATA statements.
	local_infile?: bool & true | false | *true

	// This variable specifies the timeout in seconds for attempts to acquire metadata locks.
	lock_wait_timeout?: int & >= 1 & <= 31536000 | *31536000

	// Whether mysqld was locked in memory with --memlock.log_error
	locked_in_memory?: bool & true | false | *false

	// Whether the binary log is enabled.
	log_bin?: bool & true | false

	// Holds the base name and path for the binary log files, which can be set with the --log-bin server option.
	log_bin_basename?: string

	// The name for the binary log index file, which contains the names of the binary log files.
	log_bin_index?: string

	// This variable applies when binary logging is enabled.
	log_bin_trust_function_creators?: bool & true | false | *false

	// Whether Version 2 binary logging is in use.
	log_bin_use_v1_row_events?: bool & true | false | *false

	// This variable affects binary logging of user-management statements.
	log_builtin_as_identified_by_password?: bool & true | false | *false

	// The error log output destination.
	log_error?: string

	// The verbosity of the server in writing error, warning, and note messages to the error log.
	log_error_verbosity?: int & >= 1 & <= 3 | *3

	// TABLEFILENONEThe destination or destinations for general query log and slow query log output.
	log_output?: string & "TABLE" | "FILE" | "NONE" | *"FILE"

	// If you enable this variable with the slow query log enabled, queries that are expected to retrieve all rows are logged.
	log_queries_not_using_indexes?: bool & true | false | *false

	// Whether updates received by a replica server from a source server should be logged to the replica's own binary log.Normally, a replica does not log to its own binary log any updates that are received from a source server.
	log_slave_updates?: bool & true | false | *false

	// Include slow administrative statements in the statements written to the slow query log.
	log_slow_admin_statements?: bool & true | false | *false

	// The facility for error log output written to syslog (what type of program is sending the message).
	log_syslog_facility?: string | *"daemon"

	// Whether to include the server process ID in each line of error log output written to syslog.
	log_syslog_include_pid?: bool & true | false | *true

	// The tag to be added to the server identifier in error log output written to syslog.
	log_syslog_tag?: string | *"empty string"

	// If log_queries_not_using_indexes is enabled, the log_throttle_queries_not_using_indexes variable limits the number of such queries per minute that can be written to the slow query log.
	log_throttle_queries_not_using_indexes?: int & >= 0 & <= 4294967295 | *0

	// UTCSYSTEMThis variable controls the time zone of timestamps in messages written to the error log, and in general query log and slow query log messages written to files.
	log_timestamps?: string & "UTC" | "SYSTEM" | *"UTC"

	// If a query takes longer than this many seconds, the server increments the Slow_queries status variable.
	long_query_time?: int & >= 0 & <= 31536000 | *10

	// If set to 1, all INSERT, UPDATE, DELETE, and LOCK TABLE WRITE statements wait until there is no pending SELECT or LOCK TABLE READ on the affected table.
	low_priority_updates?: bool & true | false | *false

	// This variable describes the case sensitivity of file names on the file system where the data directory is located.
	lower_case_file_system?: bool & true | false

	// Enabling this variable causes the source to verify events read from the binary log by examining checksums, and to stop with an error in the event of a mismatch.
	master_verify_checksum?: bool & true | false | *false

	// The maximum size of one packet or any generated/intermediate string, or any parameter sent by the mysql_stmt_send_long_data() C API function.
	max_allowed_packet?: int & >= 1024 & <= 1073741824 | *4194304

	// If a transaction requires more than this many bytes, the server generates a Multi-statement transaction required more than 'max_binlog_cache_size' bytes of storage error.
	max_binlog_cache_size?: int & >= 4096 & <= 18446744073709547520 | *18446744073709547520

	// If a write to the binary log causes the current log file size to exceed the value of this variable, the server rotates the binary logs (closes the current file and opens the next one).
	max_binlog_size?: int & >= 4096 & <= 1073741824 | *1073741824

	// If nontransactional statements within a transaction require more than this many bytes of memory, the server generates an error.
	max_binlog_stmt_cache_size?: int & >= 4096 & <= 18446744073709547520 | *18446744073709547520

	// After max_connect_errors successive connection requests from a host are interrupted without a successful connection, the server blocks that host from further connections.
	max_connect_errors?: int & >= 1 & <= 18446744073709551615 | *100

	// The maximum permitted number of simultaneous client connections.
	max_connections?: int & >= 1 & <= 100000 | *151

	// The maximum number of bytes of memory reserved per session for computation of normalized statement digests.
	max_digest_length?: int & >= 0 & <= 1048576 | *1024

	// The maximum number of error, warning, and information messages to be stored for display by the SHOW ERRORS and SHOW WARNINGS statements.
	max_error_count?: int & >= 0 & <= 65535 | *64

	// The execution timeout for SELECT statements, in milliseconds.
	max_execution_time?: int & >= 0 & <= 4294967295 | *0

	// This variable sets the maximum size to which user-created MEMORY tables are permitted to grow.
	max_heap_table_size?: int & >= 16384 & <= 18446744073709550592 | *16777216

	// Do not permit statements that probably need to examine more than max_join_size rows (for single-table statements) or row combinations (for multiple-table statements) or that are likely to do more than max_join_size disk seeks.
	max_join_size?: int & >= 1 & <= 18446744073709551615 | *18446744073709551615

	// The cutoff on the size of index values that determines which filesort algorithm to use.
	max_length_for_sort_data?: int & >= 4 & <= 8388608 | *1024

	// The maximum value of the points_per_circle argument to the ST_Buffer_Strategy() function.max_prepared_stmt_count
	max_points_in_geometry?: int & >= 3 & <= 1048576 | *65536

	// This variable limits the total number of prepared statements in the server.
	max_prepared_stmt_count?: int & >= 0 & <= 1048576 | *16382

	// The number of bytes to use when sorting data values.
	max_sort_length?: int & >= 4 & <= 8388608 | *1024

	// The number of times that any given stored procedure may be called recursively.
	max_sp_recursion_depth?: int & >= 0 & <= 255 | *0

	// The maximum number of simultaneous connections permitted to any given MySQL user account.
	max_user_connections?: int & >= 0 & <= 4294967295 | *0

	// The mecab_rc_file option is used when setting up the MeCab full-text parser.The mecab_rc_file option defines the path to the mecabrc configuration file, which is the configuration file for MeCab.
	mecab_rc_file?: string

	// Queries that examine fewer than this number of rows are not logged to the slow query log.multi_range_count
	min_examined_row_limit?: int & >= 0 & <= 18446744073709551615 | *0

	// The default pointer size in bytes, to be used by CREATE TABLE for MyISAM tables when no MAX_ROWS option is specified.
	myisam_data_pointer_size?: int & >= 2 & <= 7 | *6

	// The maximum amount of memory to use for memory mapping compressed MyISAM files.
	myisam_mmap_size?: int & >= 7 & <= 18446744073709551615 | *18446744073709551615

	// OFFDEFAULTBACKUPFORCEQUICKSet the MyISAM storage engine recovery mode.
	myisam_recover_options?: string & "OFF" | "DEFAULT" | "BACKUP" | "FORCE" | "QUICK" | *"OFF"

	// The size of the buffer that is allocated when sorting MyISAM indexes during a REPAIR TABLE or when creating indexes with CREATE INDEX or ALTER TABLE.myisam_stats_method
	myisam_sort_buffer_size?: int & >= 4096 & <= 18446744073709551615 | *8388608

	// nulls_unequalnulls_equalnulls_ignoredHow the server treats NULL values when collecting statistics about the distribution of index values for MyISAM tables.
	myisam_stats_method?: string & "nulls_unequal" | "nulls_equal" | "nulls_ignored" | *"nulls_unequal"

	// Use memory mapping for reading and writing MyISAM tables.mysql_native_password_proxy_users
	myisam_use_mmap?: bool & true | false | *false

	// This variable controls whether the mysql_native_password built-in authentication plugin supports proxy users.
	mysql_native_password_proxy_users?: bool & true | false | *false

	// Each client thread is associated with a connection buffer and result buffer.
	net_buffer_length?: int & >= 1024 & <= 1048576 | *16384

	// The number of seconds to wait for more data from a connection before aborting the read.
	net_read_timeout?: int & >= 1 & <= 31536000 | *30

	// If a read or write on a communication port is interrupted, retry this many times before giving up.
	net_retry_count?: int & >= 1 & <= 18446744073709551615 | *10

	// The number of seconds to wait for a block to be written to a connection before aborting the write.
	net_write_timeout?: int & >= 1 & <= 31536000 | *60

	// Defines the n-gram token size for the n-gram full-text parser.
	ngram_token_size?: int & >= 1 & <= 10 | *2

	// Whether the server is in “offline mode”, which has these characteristics:Connected client users who do not have the SUPER privilege are disconnected on the next request, with an appropriate error.
	offline_mode?: bool & true | false | *false

	// old is a compatibility variable.
	old?: bool & true | false | *false

	// When this variable is enabled, the server does not use the optimized method of processing an ALTER TABLE operation.
	old_alter_table?: bool & true | false | *false

	// The number of file descriptors available to mysqld from the operating system:At startup, mysqld reserves descriptors with setrlimit(), using the value requested at by setting this variable directly or by using the --open-files-limit option to mysqld_safe.
	open_files_limit?: int

	// Controls the heuristics applied during query optimization to prune less-promising partial plans from the optimizer search space.
	optimizer_prune_level?: int & >= 0 & <= 1 | *1

	// The maximum depth of search performed by the query optimizer.
	optimizer_search_depth?: int & >= 0 & <= 62 | *62

	// This variable controls optimizer tracing.
	optimizer_trace?: string

	// This variable enables or disables selected optimizer tracing features.
	optimizer_trace_features?: string

	// The maximum number of optimizer traces to display.
	optimizer_trace_limit?: int & >= 0 & <= 2147483647 | *1

	// The maximum cumulative size of stored optimizer traces.
	optimizer_trace_max_mem_size?: int & >= 0 & <= 4294967295 | *16384

	// The offset of optimizer traces to display.
	optimizer_trace_offset?: int

	// The path name of the file in which the server writes its process ID.
	pid_file?: string

	// The path name of the plugin directory.If the plugin directory is writable by the server, it may be possible for a user to write executable code to a file in the directory using SELECT ...
	plugin_dir?: string | *"BASEDIR/lib/plugin"

	// The number of the port on which the server listens for TCP/IP connections.
	port?: int & >= 0 & <= 65535 | *3306

	// The size of the buffer that is allocated when preloading indexes.profilingIf set to 0 or OFF (the default), statement profiling is disabled.
	preload_buffer_size?: int & >= 1024 & <= 1073741824 | *32768

	// The version of the client/server protocol used by the MySQL server.proxy_user
	protocol_version?: int & >= 0 & <= 4294967295 | *10

	// If the current client is a proxy for another user, this variable is the proxy user account name.
	proxy_user?: string

	// This system variable is for internal server use.
	pseudo_slave_mode?: bool & true | false

	// This variable is for internal server use.Changing the session value of the pseudo_thread_id system variable changes the value returned by the CONNECTION_ID() function.query_alloc_block_size
	pseudo_thread_id?: int & >= 0 & <= 2147483647 | *2147483647

	// The allocation size in bytes of memory blocks that are allocated for objects created during statement parsing and execution.
	query_alloc_block_size?: int & >= 1024 & <= 4294966272 | *8192

	// The size in bytes of the persistent buffer used for statement parsing and execution.
	query_prealloc_size?: int & >= 8192 & <= 18446744073709550592 | *8192

	// The rand_seed1 and rand_seed2 variables exist as session variables only, and can be set but not read.
	rand_seed1?: int & >= 0 & <= 4294967295

	// The size in bytes of blocks that are allocated when doing range optimization.The block size for the byte number is 1024.
	range_alloc_block_size?: int & >= 4096 & <= 4294966272 | *4096

	// STRICTIDEMPOTENTFor internal use by mysqlbinlog.
	rbr_exec_mode?: string & "STRICT" | "IDEMPOTENT" | *"STRICT"

	// Each thread that does a sequential scan for a MyISAM table allocates a buffer of this size (in bytes) for each table it scans.
	read_buffer_size?: int & >= 8192 & <= 2147479552 | *131072

	// If the read_only system variable is enabled, the server permits no client updates except from users who have the SUPER privilege.
	read_only?: bool & true | false | *false

	// This variable is used for reads from MyISAM tables, and, for any storage engine, for Multi-Range Read optimization.When reading rows from a MyISAM table in sorted order following a key-sorting operation, the rows are read through this buffer to avoid disk seeks.
	read_rnd_buffer_size?: int & >= 1 & <= 2147483647 | *262144

	// Whether client connections to the server are required to use some form of secure transport.
	require_secure_transport?: bool & true | false | *false

	// Controls whether semisynchronous replication is enabled on the source.
	rpl_semi_sync_master_enabled?: bool & true | false | *false

	// A value in milliseconds that controls how long the source waits on a commit for acknowledgment from a replica before timing out and reverting to asynchronous replication.
	rpl_semi_sync_master_timeout?: int & >= 0 & <= 4294967295 | *10000

	// The semisynchronous replication debug trace level on the source.
	rpl_semi_sync_master_trace_level?: int & >= 0 & <= 4294967295 | *32

	// The number of replica acknowledgments the source must receive per transaction before proceeding.
	rpl_semi_sync_master_wait_for_slave_count?: int & >= 1 & <= 65535 | *1

	// Controls whether the source waits for the timeout period configured by rpl_semi_sync_master_timeout to expire, even if the replica count drops to less than the number of replicas configured by rpl_semi_sync_master_wait_for_slave_count during the timeout period.When the value of rpl_semi_sync_master_wait_no_slave is ON (the default), it is permissible for the replica count to drop to less than rpl_semi_sync_master_wait_for_slave_count during the timeout period.
	rpl_semi_sync_master_wait_no_slave?: bool & true | false | *true

	// AFTER_SYNCAFTER_COMMITThis variable controls the point at which a semisynchronous source waits for replica acknowledgment of transaction receipt before returning a status to the client that committed the transaction.
	rpl_semi_sync_master_wait_point?: string & "AFTER_SYNC" | "AFTER_COMMIT" | *"AFTER_SYNC"

	// empty stringdirnameNULLThis variable is used to limit the effect of data import and export operations, such as those performed by the LOAD DATA and SELECT ...
	secure_file_priv?: string | *"platform specific"

	// OFFOWN_GTIDALL_GTIDSControls whether the server returns GTIDs to the client, enabling the client to use them to track the server state.
	session_track_gtids?: string & "OFF" | "OWN_GTID" | "ALL_GTIDS" | *"OFF"

	// Controls whether the server tracks when the default schema (database) is set within the current session and notifies the client to make the schema name available.If the schema name tracker is enabled, name notification occurs each time the default schema is set, even if the new schema name is the same as the old.For more information about session state tracking, see Section 5.1.15, “Server Tracking of Client Session State”.session_track_state_change
	session_track_schema?: bool & true | false | *true

	// Controls whether the server tracks changes to the state of the current session and notifies the client when state changes occur.
	session_track_state_change?: bool & true | false | *false

	// Controls whether the server tracks assignments to session system variables and notifies the client of the name and value of each assigned variable.
	session_track_system_variables?: string | *"time_zone, autocommit, character_set_client, character_set_results, character_set_connection"

	// OFFSTATECHARACTERISTICSControls whether the server tracks the state and characteristics of transactions within the current session and notifies the client to make this information available.
	session_track_transaction_info?: string & "OFF" | "STATE" | "CHARACTERISTICS" | *"OFF"

	// This variable is available if the server was compiled using OpenSSL (see Section 6.3.4, “SSL Library-Dependent Capabilities”).
	sha256_password_auto_generate_rsa_keys?: bool & true | false | *true

	// This variable is available if MySQL was compiled using OpenSSL (see Section 6.3.4, “SSL Library-Dependent Capabilities”).
	sha256_password_private_key_path?: string | *"private_key.pem"

	// This variable controls whether the sha256_password built-in authentication plugin supports proxy users.
	sha256_password_proxy_users?: bool & true | false | *false

	// This variable is available if MySQL was compiled using OpenSSL (see Section 6.3.4, “SSL Library-Dependent Capabilities”).
	sha256_password_public_key_path?: string | *"public_key.pem"

	// This is OFF if mysqld uses external locking (system locking), ON if external locking is disabled.
	skip_external_locking?: bool & true | false | *true

	// Whether to resolve host names when checking client connections.
	skip_name_resolve?: bool & true | false | *false

	// This variable controls whether the server permits TCP/IP connections.
	skip_networking?: bool & true | false | *false

	// This prevents people from using the SHOW DATABASES statement if they do not have the SHOW DATABASES privilege.
	skip_show_database?: bool & true | false | *false

	// If creating a thread takes longer than this many seconds, the server increments the Slow_launch_threads status variable.slow_query_log
	slow_launch_time?: int & >= 0 & <= 31536000 | *2

	// Whether the slow query log is enabled.
	slow_query_log?: bool & true | false | *false

	// The name of the slow query log file.
	slow_query_log_file?: string | *"host_name-slow.log"

	// If this variable is enabled, then after a statement that successfully inserts an automatically generated AUTO_INCREMENT value, you can find that value by issuing a statement of the following form:If the statement returns a row, the value returned is the same as if you invoked the LAST_INSERT_ID() function.
	sql_auto_is_null?: bool & true | false | *false

	// If set to OFF, MySQL aborts SELECT statements that are likely to take a very long time to execute (that is, statements for which the optimizer estimates that the number of examined rows exceeds the value of max_join_size).
	sql_big_selects?: bool & true | false | *true

	// If enabled, sql_buffer_result forces results from SELECT statements to be put into temporary tables.
	sql_buffer_result?: bool & true | false | *false

	// This variable controls whether logging to the binary log is enabled for the current session (assuming that the binary log itself is enabled).
	sql_log_bin?: bool & true | false | *true

	// OFF (enable logging)ON (disable logging)This variable controls whether logging to the general query log is disabled for the current session (assuming that the general query log itself is enabled).
	sql_log_off?: bool & true | false | *false

	// ALLOW_INVALID_DATESANSI_QUOTESERROR_FOR_DIVISION_BY_ZEROHIGH_NOT_PRECEDENCEIGNORE_SPACENO_AUTO_CREATE_USERNO_AUTO_VALUE_ON_ZERONO_BACKSLASH_ESCAPESNO_DIR_IN_CREATENO_ENGINE_SUBSTITUTIONNO_FIELD_OPTIONSNO_KEY_OPTIONSNO_TABLE_OPTIONSNO_UNSIGNED_SUBTRACTIONNO_ZERO_DATENO_ZERO_IN_DATEONLY_FULL_GROUP_BYPAD_CHAR_TO_FULL_LENGTHPIPES_AS_CONCATREAL_AS_FLOATSTRICT_ALL_TABLESSTRICT_TRANS_TABLESThe current server SQL mode, which can be set dynamically.
	sql_mode?: string & "ALLOW_INVALID_DATES" | "ANSI_QUOTES" | "ERROR_FOR_DIVISION_BY_ZERO" | "HIGH_NOT_PRECEDENCE" | "IGNORE_SPACE" | "NO_AUTO_CREATE_USER" | "NO_AUTO_VALUE_ON_ZERO" | "NO_BACKSLASH_ESCAPES" | "NO_DIR_IN_CREATE" | "NO_ENGINE_SUBSTITUTION" | "NO_FIELD_OPTIONS" | "NO_KEY_OPTIONS" | "NO_TABLE_OPTIONS" | "NO_UNSIGNED_SUBTRACTION" | "NO_ZERO_DATE" | "NO_ZERO_IN_DATE" | "ONLY_FULL_GROUP_BY" | "PAD_CHAR_TO_FULL_LENGTH" | "PIPES_AS_CONCAT" | "REAL_AS_FLOAT" | "STRICT_ALL_TABLES" | "STRICT_TRANS_TABLES" | *"ONLY_FULL_GROUP_BY STRICT_TRANS_TABLES NO_ZERO_IN_DATE NO_ZERO_DATE ERROR_FOR_DIVISION_BY_ZERO NO_AUTO_CREATE_USER NO_ENGINE_SUBSTITUTION"

	// If enabled (the default), diagnostics of Note level increment warning_count and the server records them.
	sql_notes?: bool & true | false | *true

	// If enabled (the default), the server quotes identifiers for SHOW CREATE TABLE and SHOW CREATE DATABASE statements.
	sql_quote_show_create?: bool & true | false | *true

	// If this variable is enabled, UPDATE and DELETE statements that do not use a key in the WHERE clause or a LIMIT clause produce an error.
	sql_safe_updates?: bool & true | false | *false

	// The maximum number of rows to return from SELECT statements.
	sql_select_limit?: int & >= 0 & <= 18446744073709551615 | *18446744073709551615

	// This variable controls whether single-row INSERT statements produce an information string if warnings occur.
	sql_warnings?: bool & true | false | *false

	// The path name of the Certificate Authority (CA) certificate file in PEM format.
	ssl_ca?: string | *"NULL"

	// The path name of the directory that contains trusted SSL Certificate Authority (CA) certificate files in PEM format.
	ssl_capath?: string | *"NULL"

	// The path name of the server SSL public key certificate file in PEM format.If the server is started with ssl_cert set to a certificate that uses any restricted cipher or cipher category, the server starts with support for encrypted connections disabled.
	ssl_cert?: string | *"NULL"

	// The list of permissible ciphers for connection encryption.
	ssl_cipher?: string | *"NULL"

	// The path name of the file containing certificate revocation lists in PEM format.
	ssl_crl?: string | *"NULL"

	// The path of the directory that contains certificate revocation-list files in PEM format.
	ssl_crlpath?: string | *"NULL"

	// The path name of the server SSL private key file in PEM format.
	ssl_key?: string | *"NULL"

	// Sets a soft upper limit for the number of cached stored routines per connection.
	stored_program_cache?: int & >= 16 & <= 524288 | *256

	// If the read_only system variable is enabled, the server permits no client updates except from users who have the SUPER privilege.
	super_read_only?: bool & true | false | *false

	// Controls how often the MySQL server synchronizes the binary log to disk.sync_binlog=0: Disables synchronization of the binary log to disk by the MySQL server.
	sync_binlog?: int & >= 0 & <= 4294967295 | *1

	// The server system time zone.
	system_time_zone?: string

	// The number of table definitions (from .frm files) that can be stored in the table definition cache.
	table_definition_cache?: int & >= 400 & <= 524288

	// The number of open tables for all threads.
	table_open_cache?: int & >= 1 & <= 524288 | *2000

	// The number of open tables cache instances.
	table_open_cache_instances?: int & >= 1 & <= 64 | *16

	// How many threads the server should cache for reuse.
	thread_cache_size?: int & >= 0 & <= 16384

	// no-threadsone-thread-per-connectionloaded-dynamicallyThe thread-handling model used by the server for connection threads.
	thread_handling?: string & "no-threads" | "one-thread-per-connection" | "loaded-dynamically" | *"one-thread-per-connection"

	// This variable controls which algorithm the thread pool plugin uses:A value of 0 (the default) uses a conservative low-concurrency algorithm which is most well tested and is known to produce very good results.A value of 1 increases the concurrency and uses a more aggressive algorithm which at times has been known to perform 5–10% better on optimal thread counts, but has degrading performance as the number of connections increases.
	thread_pool_algorithm?: int & >= 0 & <= 1 | *0

	// This variable affects queuing of new statements prior to execution.
	thread_pool_high_priority_connection?: int & >= 0 & <= 1 | *0

	// The maximum permitted number of unused threads in the thread pool.
	thread_pool_max_unused_threads?: int & >= 0 & <= 4096 | *0

	// This variable affects statements waiting for execution in the low-priority queue.
	thread_pool_prio_kickup_timer?: int & >= 0 & <= 4294967294 | *1000

	// The number of thread groups in the thread pool.
	thread_pool_size?: int & >= 1 & <= 64 | *16

	// This variable affects executing statements.
	thread_pool_stall_limit?: int & >= 4 & <= 600 | *6

	// The stack size for each thread.
	thread_stack?: int & >= 131072 & <= 18446744073709550592 | *262144

	// The current time zone.
	time_zone?: string | *"SYSTEM"

	// Set the time for this client.
	timestamp?: int & >= 1 & <= 2147483647

	// The maximum size of internal in-memory temporary tables.
	tmp_table_size?: int & >= 1024 & <= 18446744073709551615 | *16777216

	// The path of the directory to use for creating temporary files.
	tmpdir?: string

	// The amount in bytes by which to increase a per-transaction memory pool which needs memory.
	transaction_alloc_block_size?: int & >= 1024 & <= 131072 | *8192

	// There is a per-transaction memory pool from which various transaction-related allocations take memory.
	transaction_prealloc_size?: int & >= 1024 & <= 131072 | *4096

	// OFFMURMUR32XXHASH64OFFMURMUR32Defines the algorithm used to generate a hash identifying the writes associated with a transaction.
	transaction_write_set_extraction?: string | *"OFF"

	// If set to 1 (the default), uniqueness checks for secondary indexes in InnoDB tables are performed.
	unique_checks?: bool & true | false | *true

	// This variable controls whether updates to a view can be made when the view does not contain all columns of the primary key defined in the underlying table, if the update statement contains a LIMIT clause.
	updatable_views_with_limit?: bool & true | false | *false

	// The CMake configuration program has a COMPILATION_COMMENT option that permits a comment to be specified when building MySQL.
	version_comment?: string

	// The type of the server binary.version_compile_os
	version_compile_machine?: string

	// The type of operating system on which MySQL was built.wait_timeout
	version_compile_os?: string

	// other parameters
	// reference mysql parameters
	...
}

// SectionName is section name
[SectionName=_]: #MysqlParameter
