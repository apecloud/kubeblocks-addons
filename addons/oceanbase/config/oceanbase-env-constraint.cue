#OBPortEnvParameters: {
	COMP_MYSQL_PORT:   int & >=1
	COMP_RPC_PORT:     int & >=1
	SERVICE_PORT:      int & >=1
	MANAGER_PORT:      int & >=1
	CONF_MANAGER_PORT: int & >=1
	OB_SERVICE_PORT:   int & >=1
}

configuration: #OBPortEnvParameters & {
}
