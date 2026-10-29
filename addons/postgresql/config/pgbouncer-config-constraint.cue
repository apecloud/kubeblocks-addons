#PgBouncerParameters: {
	pool_mode:            "session"
	max_client_conn:      int & >=1 & <=100000
	default_pool_size:    int & >=1 & <=10000
	min_pool_size:        int & >=0 & <=10000
	reserve_pool_size:    int & >=0 & <=10000
	reserve_pool_timeout: int & >=0 & <=3600
	max_db_connections:   int & >=1 & <=10000
	max_user_connections: int & >=1 & <=10000
	server_idle_timeout:  int & >=0 & <=86400
	server_lifetime:      int & >=0 & <=604800
	query_wait_timeout:   int & >=0 & <=86400
	client_idle_timeout:  int & >=0 & <=604800
}
