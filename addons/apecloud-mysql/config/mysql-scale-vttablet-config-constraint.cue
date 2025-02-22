#VtTabletParameter: {

	// Connection timeout to mysqld in milliseconds. (0 for no timeout, default 500)
	db_connect_timeout_ms: int & >=0

	// Enable or disable logs. (default true)
	enable_logs: bool

	// Enable or disable query log. (default true)
	enable_query_log: bool

	// Interval between health checks. (default 20s)
	health_check_interval: =~"[-+]?([0-9]*(\\.[0-9]*)?[a-z]+)+$"

	// Time to wait for a remote operation. (default 15s)
	remote_operation_timeout: =~"[-+]?([0-9]*(\\.[0-9]*)?[a-z]+)+$"

	// Delay between retries of updates to keep the tablet and its shard record in sync. (default 30s)
	shard_sync_retry_delay: =~"[-+]?([0-9]*(\\.[0-9]*)?[a-z]+)+$"

	// Table acl config mode. Valid values are: simple, mysqlbased. (default simple)
	table_acl_config_mode: string & "simple" | "mysqlbased"

	// path to table access checker config file (json file);
	table_acl_config: string

	// Ticker to reload ACLs. Duration flag, format e.g.: 30s. Default: 30s
	table_acl_config_reload_interval: =~"[-+]?([0-9]*(\\.[0-9]*)?[a-z]+)+$"

	// only allow queries that pass table acl checks if true
	queryserver_config_strict_table_acl: bool

	// if this flag is true, vttablet will fail to start if a valid tableacl config does not exist
	enforce_tableacl_config: bool

	// query server read pool size, connection pool is used by regular queries (non streaming, not in a transaction)
	queryserver_config_pool_size: int & >=0

	// query server stream connection pool size, stream pool is used by stream queries: queries that return results to client in a streaming fashion
	queryserver_config_stream_pool_size: int & >=0

	// query server transaction cap is the maximum number of transactions allowed to happen at any given point of a time for a single vttablet. E.g. by setting transaction cap to 100, there are at most 100 transactions will be processed by a vttablet and the 101th transaction will be blocked (and fail if it cannot get connection within specified timeout)
	queryserver_config_transaction_cap: int & >=0

	// the size of database connection pool in non transaction dml
	non_transactional_dml_database_pool_size: int & >=1

	// the number of rows to be processed in one batch by default
	non_transactional_dml_default_batch_size: int & >=1

	// the interval of batch processing in milliseconds by default
	non_transactional_dml_default_batch_interval: int & >=1

	// the interval of table GC in hours
	non_transactional_dml_table_gc_interval: int & >=1

	// the interval of job scheduler running in seconds
	non_transactional_dml_job_manager_running_interval: int & >=1

	// the interval of throttle check in milliseconds
	non_transactional_dml_throttle_check_interval: int & >=1

	// the threshold of batch size
	non_transactional_dml_batch_size_threshold: int & >=1 & <=1000000

	// final threshold = ratio * non_transactional_dml_batch_size_threshold / table index numbers
	non_transactional_dml_batch_size_threshold_ratio: float & >=0 & <=1
}

// SectionName is section name
[SectionName=_]: #VtTabletParameter
