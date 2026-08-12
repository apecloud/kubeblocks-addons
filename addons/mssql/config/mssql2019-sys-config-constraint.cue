// Copyright ApeCloud Co., Ltd. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

#SysConfigurationsParameters: {
		// Enable ad hoc distributed queries
		"ad hoc distributed queries"?: int & >=0 & <= 1 | *0

		// Enable Database Mail XPs
		"database mail xps"?: int & >=0 & <= 1 | *0

		// Blocked process threshold (in seconds)
		"blocked process threshold (s)"?: int & >=0 & <=86400 | *0

		// Enable Common Language Runtime
		"clr enabled"?: int & >=0 & <= 1 | *0

		// Control SQL Server CLR security mode
		"clr strict security"?: int & >=0 & <= 1 | *0

		// Cost threshold for parallelism
		"cost threshold for parallelism"?: int & >=0 & <=32767 | *5

		// Default full-text language
		"default full-text language"?: int & >=0 & <=2147483647 | *1033

		// Default language
		"default language"?: int & >=0 & <=9999 | *0

		// Filestream access level
		"filestream access level"?: int & >=0 & <=2 | *0

		// Maximum degree of parallelism
		"max degree of parallelism"?: int & >=0 & <=32767 | *0

		// Remote query timeout (in seconds)
		"remote query timeout (s)"?: int & >=0 & <=2147483647 | *600

		// Remote login timeout (in seconds)
		"remote login timeout (s)"?: int & >=0 & <=2147483647 | *10

		// Query wait (in seconds)
		"query wait (s)"?: int & >=-1 & <=2147483647 | *-1

		// Optimize for ad hoc workloads
		"optimize for ad hoc workloads"?: int & >=0 & <= 1 | *0

		// Nested triggers
		"nested triggers"?: int & >=0 & <= 1 | *1

		// Maximum worker threads
		"max worker threads"?: int & >=128 & <=65535 | *0

		// Maximum text replication size (in bytes)
		"max text repl size (b)"?: int & >=0 & <=2147483647 | *65536

		// Enable remote procedure transactions
		"remote proc trans"?: int & >=0 & <= 1 | *0

		// Query governor cost limit
		"query governor cost limit"?: int & >=0 & <=2147483647 | *0

		// Recovery interval (in minutes)
		"recovery interval (min)"?: int & >=0 & <=32767 | *0

		// Minimum memory per query (in KB)
		"min memory per query (kb)"?: int & >=512 & <=2147483647 | *1024

		// In-doubt xact resolution
		"in-doubt xact resolution"?: int & >=0 & <=2 | *0
}

configuration: #SysConfigurationsParameters & {}
