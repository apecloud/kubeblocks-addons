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

	...
}

configuration: {
	pgbouncer: #PgBouncerParameter
	...
}
