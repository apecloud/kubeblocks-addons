#PgBouncerParameter: {
	// Pooling mode used for new client connections.
	pool_mode?: "session" | "transaction" | "statement" | *"session"

	// Maximum number of client connections accepted by one PgBouncer instance.
	max_client_conn?: int & >=1 & <=999999 | *500

	// Default number of backend connections for each user/database pool.
	default_pool_size?: int & >=1 & <=999999 | *20

	// Minimum number of backend connections retained for each user/database pool.
	min_pool_size?: int & >=0 & <=999999 | *5

	// Additional backend connections allowed when a pool is exhausted.
	reserve_pool_size?: int & >=0 & <=999999 | *5

	// Maximum number of backend connections to one database per PgBouncer instance. Zero means unlimited.
	max_db_connections?: int & >=0 & <=999999 | *80

	// Maximum number of backend connections for one user per PgBouncer instance. Zero means unlimited.
	max_user_connections?: int & >=0 & <=999999 | *80
}

#PgBouncerConfig: {
	#PgBouncerParameter

	listen_addr:               "*"
	listen_port:               6432
	unix_socket_dir:           "/tmp"
	unix_socket_mode:          "0770"
	auth_file:                 "/etc/pgbouncer/userlist.txt"
	auth_type:                 "md5"
	auth_user:                 "postgres"
	auth_query:                "SELECT rolname, CASE WHEN rolvaliduntil IS NOT NULL AND rolvaliduntil < pg_catalog.now() THEN NULL ELSE rolpassword END FROM pg_catalog.pg_authid WHERE rolname=$1 AND rolcanlogin"
	auth_dbname:               "postgres"
	admin_users:               "postgres"
	stats_users:               "postgres"
	client_tls_sslmode:        "disable"
	server_tls_sslmode:        "disable"
	ignore_startup_parameters: "extra_float_digits"
	reserve_pool_timeout:      5
	server_idle_timeout:       600
	server_lifetime:           3600
	query_wait_timeout:        120
	client_idle_timeout:       0
}

#PgBouncerConfiguration: {
	pgbouncer: #PgBouncerConfig
}

configuration: #PgBouncerConfiguration
