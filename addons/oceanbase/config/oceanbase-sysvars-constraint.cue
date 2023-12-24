// https://github.com/oceanbase/oceanbase/blob/develop/src/share/system_variable/ob_system_variable_init.json

#OBSysVariables: {

	// The number of simultaneous client connections allowed.
	max_connections: int & >=1

	...
}

configuration: #OBSysVariables & {
}
