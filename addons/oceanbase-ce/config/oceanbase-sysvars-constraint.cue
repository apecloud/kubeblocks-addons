// generated by tools
// source: https://raw.githubusercontent.com/oceanbase/oceanbase/develop/src/share/system_variable/ob_system_variable_init.json
#OBSysVariables: {

	//
	ob_bnl_join_cache_size: int & >=1 & <=9223372036854775807

	//
	sql_warnings: string & "0" | "1" | "OFF" | "ON"

	// specifies the default length semantics to use for VARCHAR2 and CHAR table columns, user-defined object attributes, and PL/SQL variables in database objects created in the session. SYS user use BYTE intead of NLS_LENGTH_SEMANTICS.
	nls_length_semantics: string

	//
	net_read_timeout: int & >=1 & <=31536000

	// The server system time zone
	system_time_zone: string

	// specifies whether return session state change info in ok packet
	session_track_state_change: string & "0" | "1" | "OFF" | "ON"

	// Abort a recursive common table expression if it does more than this number of iterations.
	cte_max_recursion_depth: int & >=0 & <=4294967295

	// specifies the characters to use as the decimal character and group separator, overrides those characters defined implicitly by NLS_TERRITORY.
	nls_numeric_characters: string

	// control whether lob use partial update
	log_row_value_options: string

	// how table database names are stored and compared, 0 means stored using the lettercase in the CREATE_TABLE or CREATE_DATABASE statement. Name comparisons are case sensitive; 1 means that table and database names are stored in lowercase abd name comparisons are not case sensitive.
	lower_case_table_names: int & >=0 & <=2

	// this value is true if we have executed set transaction stmt, until a transaction commit(explicit or implicit) successfully
	ob_proxy_set_trx_executed: string & "0" | "1" | "OFF" | "ON"

	//
	unique_checks: string & "0" | "1" | "OFF" | "ON"

	// If set true, transaction open the elr optimization.
	ob_early_lock_release: string & "0" | "1" | "OFF" | "ON"

	// determines whether an error is reported when there is data loss during an implicit or explicit character type conversion between NCHAR/NVARCHAR2 and CHAR/VARCHAR2.
	nls_nchar_conv_excp: string

	// Enable the flashback of table truncation.
	ob_enable_truncate_flashback: string & "0" | "1" | "OFF" | "ON"

	//
	div_precision_increment: int & >=0 & <=30

	// enable mysql sql safe updates
	sql_safe_updates: string & "0" | "1" | "OFF" | "ON"

	// The smallest unit of memory allocated by the query cache(not used yet, only sys var compatible)
	query_cache_min_res_unit: int & >=0 & <=18446744073709551615

	//
	default_password_lifetime: int & >=0 & <=65535

	// The server character set
	character_set_server: int

	//
	lc_messages: string

	// Global debug sync facility
	ob_global_debug_sync: string

	// specifies the encryption algorithm used in the functions aes_encrypt and aes_decrypt
	block_encryption_mode: string & "aes-128-ecb" | "aes-192-ecb" | "aes-256-ecb" | "aes-128-cbc" | "aes-192-cbc" | "aes-256-cbc" | "aes-128-cfb1" | "aes-192-cfb1" | "aes-256-cfb1" | "aes-128-cfb8" | "aes-192-cfb8" | "aes-256-cfb8" | "aes-128-cfb128" | "aes-192-cfb128" | "aes-256-cfb128" | "aes-128-ofb" | "aes-192-ofb" | "aes-256-ofb"

	// specifies the dual currency symbol for the territory. The default is the dual currency symbol defined in the territory of your current language environment.
	nls_dual_currency: string

	// The number of seconds the server waits for activity on an interactive connection before closing it.
	interactive_timeout: int & >=1 & <=31536000

	// specifies whether return system variables change info in ok packet
	session_track_system_variables: string

	// query may not be allowed to execute if its network usage isnt less than this value.
	sql_throttle_network: int

	// JIT execution engine mode, default is AUTO
	ob_enable_jit: string & "OFF" | "AUTO" | "FORCE"

	//
	ssl_crlpath: string

	// default lob inrow threshold config
	ob_default_lob_inrow_threshold: int

	//
	general_log: string & "0" | "1" | "OFF" | "ON"

	// The memory allocated to store results from old queries(not used yet)
	query_cache_size: int & >=0 & <=18446744073709551615

	//
	last_insert_id: int & >=0 & <=18446744073709551615

	//
	long_query_time: int & >=0

	// The default storage engine of OceanBase
	default_storage_engine: string

	//
	ob_last_schema_version: int

	// Enable use sql plan baseline
	optimizer_use_sql_plan_baselines: string & "0" | "1" | "OFF" | "ON"

	// specifies the minimum execution time a table scan should have before it's considered for automatic degree of parallelism, variable unit is milliseconds
	parallel_min_scan_time_threshold: int & >=10 & <=9223372036854775807

	//
	error_count: int

	//
	tx_read_only: string & "0" | "1" | "OFF" | "ON"

	// this value is global variables last modified time when server session create, used for proxy to judge whether global vars has changed between two server session
	ob_proxy_global_variables_version: int

	// query may not be allowed to execute if its rt isnt less than this value.
	sql_throttle_rt: int

	// the max duration of waiting on row lock of one transaction
	ob_trx_lock_timeout: int

	// Lets you control conditional compilation of each PL/SQL unit independently.
	plsql_ccflags: string

	// The character set in which statements are sent by the client
	character_set_client: int

	// specifies tenant resource plan.
	resource_manager_plan: string

	//
	tmpdir: string

	// enable aggregation function to be push-downed through exchange nodes
	ob_enable_aggregation_pushdown: string & "0" | "1" | "OFF" | "ON"

	// When the DRC system copies data into the target cluster, it needs to be set to the CLUSTER_ID that should be written into commit log of OceanBase, in order to avoid loop replication of data. Normally, it does not need to be set, and OceanBase will use the default value, which is the CLUSTER_ID of current cluster of OceanBase. 0 indicates it is not set, please do not set it to 0
	ob_org_cluster_id: int & >=0 & <=4294967295

	// current priority used for SQL throttling
	sql_throttle_current_priority: int

	// The maximum query result set that can be cached by the query cache(not used yet, only sys var compatible)
	query_cache_limit: int & >=0 & <=18446744073709551615

	//
	ssl_crl: string

	//
	max_connections: int & >=1 & <=2147483647

	//
	time_format: string

	// server uuid
	server_uuid: string

	// If set true, sql will update sys variable while schema version changed.
	ob_check_sys_variable: string & "0" | "1" | "OFF" | "ON"

	// in certain case, warnings would be transformed to errors
	innodb_strict_mode: string & "0" | "1" | "OFF" | "ON"

	//
	time_zone: string

	//
	init_connect: string

	//
	hostname: string

	//
	validate_password_policy: string & "low" | "medium"

	// set default wait time ms for runtime filter, default is 10ms
	runtime_filter_wait_time_ms: int

	// Transaction Isolcation Levels: READ-UNCOMMITTED READ-COMMITTED REPEATABLE-READ SERIALIZABLE
	tx_isolation: string

	// When the recycle bin is enabled, dropped tables and their dependent objects are placed in the recycle bin. When the recycle bin is disabled, dropped tables and their dependent objects are not placed in the recycle bin; they are just dropped.
	recyclebin: string & "0" | "1" | "OFF" | "ON"

	// control row cells to logged
	binlog_row_image: string & "MINIMAL" | "NOBLOB" | "FULL"

	// The time limit for regular expression matching operations, default unit is milliseconds
	regexp_time_limit: int & >=0 & <=2147483647

	// specifies the string to use as the international currency symbol for the C number format element. The default value of this parameter is determined by NLS_TERRITORY
	nls_iso_currency: string

	// Whether to have query cache or not(not used yet, only compatible)
	have_query_cache: string

	// Query timeout in microsecond(us)
	ob_query_timeout: int

	// specifies the string to use as the local currency symbol for the L number format element. The default value of this parameter is determined by NLS_TERRITORY.
	nls_currency: string

	// The character set which server should translate to before shipping result sets or error message back to the client
	character_set_results: int

	// This variable reports only on the status of binary logging(not used yet, only sys var compatible)
	log_bin: string & "0" | "1" | "OFF" | "ON"

	//
	validate_password_mixed_case_count: int & >=0 & <=2147483647

	// The national character set which should be translated to response nstring data
	ncharacter_set_connection: int

	//
	character_set_filesystem: int

	//
	timestamp: int & >=0

	//
	protocol_version: int

	// TLSv1,TLSv1.1,TLSv1.2
	tls_version: string

	// auto_increment service cache size
	auto_increment_cache_size: int & >=1 & <=100000000

	// The character set which should be translated to after receiving the statement
	character_set_connection: int

	// memory usage percentage of plan_cache_limit at which plan cache eviction will be trigger
	ob_plan_cache_evict_high_percentage: int & >=0 & <=100

	// What DBMS is OceanBase compatible with? MYSQL means it behaves like MySQL while ORACLE means it behaves like Oracle.
	ob_compatibility_mode: string & "MYSQL" | "ORACLE"

	// specifies whether automatic degree of parallelism will be enabled
	parallel_degree_policy: string & "MANUAL" | "AUTO"

	//
	sql_select_limit: int & >=0 & <=9223372036854775807

	// enables or disables the reporting of warning messages by the PL/SQL compiler, and specifies which warning messages to show as errors.
	plsql_warnings: string

	// max stale time(us) for weak read query
	ob_max_read_stale_time: int

	// control whether use show trace
	ob_enable_show_trace: string & "0" | "1" | "OFF" | "ON"

	// whether use traditional mode for timestamp
	explicit_defaults_for_timestamp: string & "0" | "1" | "OFF" | "ON"

	// OFF = Do not cache or retrieve results. ON = Cache all results except SELECT SQL_NO_CACHE ... queries. DEMAND = Cache only SELECT SQL_CACHE ... queries(not used yet)
	query_cache_type: string & "OFF" | "ON" | "DEMAND"

	// when query is with topk hint, is_result_accurate indicates whether the result is acuurate or not
	is_result_accurate: string & "0" | "1" | "OFF" | "ON"

	// The percentage limitation of tenant memory for SQL execution.
	ob_sql_work_area_percentage: int & >=0 & <=100

	// The character set used by the server for storing identifiers.
	character_set_system: int

	//
	version_compile_os: string

	// percentage of tenant memory resources that can be used by plan cache
	ob_plan_cache_percentage: int & >=0 & <=100

	//
	sql_notes: string & "0" | "1" | "OFF" | "ON"

	//
	tmp_table_size: int & >=1024 & <=18446744073709551615

	// The maximum available memory in bytes for the internal stack used for regular expression matching operations
	regexp_stack_limit: int & >=0 & <=2147483647

	// memory usage percentage  of plan_cache_limit at which plan cache eviction will be stopped
	ob_plan_cache_evict_low_percentage: int & >=0 & <=100

	// set to 1 (the default by MySQL), foreign key constraints are checked. If set to 0, foreign key constraints are ignored
	foreign_key_checks: string & "0" | "1" | "OFF" | "ON"

	// the trace id of current executing statement
	ob_statement_trace_id: string

	// wether use sql audit in session
	ob_enable_sql_audit: string & "0" | "1" | "OFF" | "ON"

	// Debug sync facility
	debug_sync: string

	// Max packet length to send to or receive from the server
	max_allowed_packet: int & >=1024 & <=1073741824

	//
	max_user_connections: int & >=0 & <=4294967295

	//
	max_execution_time: int

	//
	ssl_cert: string

	// The collation of the default database
	collation_database: int

	// Indicate features that observer supports, readonly after modified by first observer
	ob_capability_flag: int & >=0 & <=18446744073709551615

	// PL/SQL timeout in microsecond(us)
	ob_pl_block_timeout: int & >=0 & <=9223372036854775807

	// query cache wirte lock for MyISAM engine (not used yet, only sys var compatible)
	query_cache_wlock_invalidate: string & "0" | "1" | "OFF" | "ON"

	// The stmt interval timeout of transaction(us)
	ob_trx_idle_timeout: int

	// read consistency level: 3=STRONG, 2=WEAK, 1=FROZEN
	ob_read_consistency: string & "" | "FROZEN" | "WEAK" | "STRONG"

	// whether use plan cache in session
	ob_enable_plan_cache: string & "0" | "1" | "OFF" | "ON"

	//
	validate_password_number_count: int & >=0 & <=2147483647

	// control optimizer dynamic sample level
	optimizer_dynamic_sampling: int & >=0 & <=1

	//
	sql_mode: int

	// specifies the default characterset of the database, This parameter defines the encoding of the data in the NCHAR, NVARCHAR2 and NCLOB columns of a table.
	nls_nchar_characterset: string

	// The character set of the default database
	character_set_database: int

	// specifies the collation behavior of the database session. value can be BINARY | LINGUISTIC | ANSI
	nls_comp: string

	// specifies the default characterset of the database, This parameter defines the encoding of the data in the CHAR, VARCHAR2, LONG and CLOB columns of a table.
	nls_characterset: string

	//
	validate_password_special_char_count: int & >=0 & <=2147483647

	// optimizer_capture_sql_plan_baselines enables or disables automitic capture plan baseline.
	optimizer_capture_sql_plan_baselines: string & "0" | "1" | "OFF" | "ON"

	//
	license: string

	// This variable specifies the server ID(not used yet, only sys var compatible)
	server_id: int & >=0 & <=4294967295

	//
	autocommit: string & "0" | "1" | "OFF" | "ON"

	// ip white list for tenant, support % and _ and multi ip(separated by commas), support ip match and wild match
	ob_tcp_invited_nodes: string

	// specifies the collating sequence for character value comparison in various SQL operators and clauses.
	nls_sort: string

	// This variable is a synonym for the last_insert_id variable. It exists for compatibility with other database systems.
	identity: int & >=0 & <=18446744073709551615

	// query may not be allowed to execute if its number of IOs isnt less than this value.
	sql_throttle_io: int

	// the routing policy of obproxy/java client and observer internal retry, 1=READONLY_ZONE_FIRST, 2=ONLY_READONLY_ZONE, 3=UNMERGE_ZONE_FIRST, 4=UNMERGE_FOLLOWER_FIRST
	ob_route_policy: string & "" | "READONLY_ZONE_FIRST" | "ONLY_READONLY_ZONE" | "UNMERGE_ZONE_FIRST" | "UNMERGE_FOLLOWER_FIRST"

	// specifies the name of the territory whose conventions are to be followed for day and week numbering, establishes the default date format, the default decimal character and group separator, and the default ISO and local currency symbols.
	nls_territory: string

	// whether do the checksum of the packet between the client and the server
	ob_enable_transmission_checksum: string & "0" | "1" | "OFF" | "ON"

	// specifies the default date format to use with the TO_CHAR and TO_DATE functions, (YYYY-MM-DD HH24:MI:SS) is Common value
	nls_date_format: string

	// store trace info
	ob_trace_info: string

	// control whether print svr_ip,execute_time,trace_id
	ob_enable_rich_error_msg: string & "0" | "1" | "OFF" | "ON"

	// Buffer length for TCP/IP and socket communication
	net_buffer_length: int & >=1024 & <=1048576

	//
	datadir: string

	//
	have_profiling: string

	//
	ssl_ca: string

	// Indicate whether sql stmt hit right partition, readonly to user, modify by ob
	ob_proxy_partition_hit: string & "0" | "1" | "OFF" | "ON"

	// Indicate current client session user privilege, readonly after modified by first observer
	ob_proxy_user_privilege: int & >=0 & <=9223372036854775807

	// the dir to place plugin dll
	plugin_dir: string

	// specifies the language to use for the spelling of day and month names and date abbreviations (a.m., p.m., AD, BC) returned by the TO_DATE and TO_CHAR functions.
	nls_date_language: string

	//
	connect_timeout: int & >=2 & <=31536000

	// specifies the default language of the database, used for messages, day and month names, the default sorting mechanism, the default values of NLS_DATE_LANGUAGE and NLS_SORT.
	nls_language: string

	// limits the degree of parallelism used by the optimizer when automatic degree of parallelism is enabled
	parallel_degree_limit: int & >=0 & <=9223372036854775807

	//
	version_comment: string

	// query may not be allowed to execute if its number of logical reads isnt less than this value.
	sql_throttle_logical_reads: int

	//
	ssl_cipher: string

	// this variable causes the source to write a checksum for each event in the binary log(not used yet, only sys var compatible)
	binlog_checksum: string

	// log level in session
	ob_log_level: string

	// The number of seconds the server waits for activity on a noninteractive connection before closing it.
	wait_timeout: int & >=1 & <=31536000

	// The server collation
	collation_server: int

	//
	read_only: string & "0" | "1" | "OFF" | "ON"

	//
	default_authentication_plugin: string

	// This system variable affects row-based logging only(not used yet, only sys var compatible)
	binlog_rows_query_log_events: string & "0" | "1" | "OFF" | "ON"

	// set runtime filter type, including the bloom_filter/range/in filter
	runtime_filter_type: string

	// The collation which the server should translate to after receiving the statement
	collation_connection: int

	// the percentage limitation of some temp tablespace size in tenant disk.
	ob_temp_tablespace_size_percentage: int

	// specifies which calendar system Oracle uses.
	nls_calendar: string

	// The variable determines how OceanBase should handle an ambiguous boundary datetime value a case in which it is not clear whether the datetime is in standard or daylight saving time
	error_on_overlap_time: string & "0" | "1" | "OFF" | "ON"

	//
	ssl_capath: string

	// limit the effect of data import and export operations
	secure_file_priv: string

	//
	auto_increment_increment: int & >=1 & <=65535

	// The limited percentage of tenant memory for sql audit
	ob_sql_audit_percentage: int & >=0 & <=80

	// set max size for single runtime bloom filter, default is 2GB
	runtime_bloom_filter_max_size: int

	// specifies whether return schema change info in ok packet
	session_track_schema: string & "0" | "1" | "OFF" | "ON"

	//
	version_compile_machine: string

	//
	have_ssl: string

	//
	group_concat_max_len: int & >=4 & <=18446744073709551615

	//
	warning_count: int

	// number of threads allowed to run parallel statements before statement queuing will be used.
	parallel_servers_target: int & >=0 & <=9223372036854775807

	// Transaction access mode
	transaction_read_only: string & "0" | "1" | "OFF" | "ON"

	// set max in number for runtime in filter, default is 1024
	runtime_filter_max_in_num: int & >=0 & <=10240

	//
	disabled_storage_engines: string

	//
	sql_quote_show_create: string & "0" | "1" | "OFF" | "ON"

	//
	ssl_key: string

	// Indicate how many bytes the interm result manager can alloc most for this tenant
	ob_interm_result_mem_limit: int

	//
	auto_increment_offset: int & >=1 & <=65535

	// The max duration of one transaction
	ob_trx_timeout: int

	// The number of times that any given stored procedure may be called recursively.
	max_sp_recursion_depth: int & >=0 & <=255

	//
	local_infile: string & "0" | "1" | "OFF" | "ON"

	//
	version: string

	// whether can select from index table
	ob_enable_index_direct_select: string & "0" | "1" | "OFF" | "ON"

	// The name of tracefile.
	tracefile_identifier: string

	//
	lock_wait_timeout: int & >=1 & <=31536000

	// Transaction Isolcation Levels: READ-UNCOMMITTED READ-COMMITTED REPEATABLE-READ SERIALIZABLE
	transaction_isolation: string

	// percentage of tenant memory resources that can be used by tenant meta data
	ob_reserved_meta_memory_percentage: int & >=1 & <=100

	// whether needs to do parameterization? EXACT - query will not do parameterization; FORCE - query will do parameterization.
	cursor_sharing: string & "FORCE" | "EXACT"

	// enabling a series of optimizer features based on an OceanBase release number
	optimizer_features_enable: string

	//
	have_openssl: string

	// whether use transform in session
	ob_enable_transformation: string & "0" | "1" | "OFF" | "ON"

	// sql throttle priority, query may not be allowed to execute if its priority isnt greater than this value.
	sql_throttle_priority: int

	// query may not be allowed to execute if its CPU usage isnt less than this value.
	sql_throttle_cpu: int

	// set the binary logging format(not used yet, only sys var compatible)
	binlog_format: string & "MIXED" | "STATEMENT" | "ROW"

	// The safe weak read snapshot version in one server
	ob_safe_weak_read_snapshot: int & >=0 & <=9223372036854775807

	// specifies the default date format to use with the TO_CHAR and TO_TIMESTAMP functions, (YYYY-MM-DD HH24:MI:SS.FF) is Common value
	nls_timestamp_format: string

	//
	validate_password_check_user_name: string & "on" | "off"

	// indicate whether the Performance Schema is enabled
	performance_schema: string & "0" | "1" | "OFF" | "ON"

	//
	net_write_timeout: int & >=1 & <=31536000

	//
	concurrent_insert: string

	// specifies the default timestamp with time zone format to use with the TO_CHAR and TO_TIMESTAMP_TZ functions, (YYYY-MM-DD HH24:MI:SS.FF TZR TZD) is common value
	nls_timestamp_tz_format: string

	//
	validate_password_length: int & >=0 & <=2147483647

	//
	sql_auto_is_null: string & "0" | "1" | "OFF" | "ON"

	...
}

configuration: #OBSysVariables & {
}
