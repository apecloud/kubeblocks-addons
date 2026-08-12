// Copyright ApeCloud Co., Ltd. All Rights Reserved.
// SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

#EULAParameters: {
		// accepteula is an important license agreement-related parameter during the installation and operation of SQL Server, which means "End User License Agreement Acceptance".
    accepteula?: string & "Y" | *"Y"
}

// Coredump section parameters
#CoredumpParameters: {
		// Determines whether SQL Server captures both mini and full memory dumps when a critical error occurs.
    captureminiandfull?: bool | *true
    // Specifies the type of memory dump to generate for crash diagnostics.
    coredumptype?: string & "full" | "mini" | "miniplus" | "filtered" | *"miniplus"
    // Defines a custom folder path where SQL Server stores generated memory dump files.
    customdumpdirectory?: string | *"/var/opt/mssql/dumps"
}

// Network section parameters
#NetworkParameters: {
		// If 1, then SQL Server forces all connections to be encrypted. By default, this option is 0.
    forceencryption?: int & (0 | 1) | *1
    // The absolute path to the certificate file that SQL Server uses for TLS
    tlscert?: string | *"/etc/ssl/certs/mssql.pem"
    // The absolute path to the private key file that SQL Server uses for TLS
    tlskey?: string | *"/etc/ssl/private/mssql.key"
    // A comma-separated list of which TLS protocols are allowed by SQL Server. SQL Server always attempts to negotiate the strongest allowed protocol. If a client doesn't support any allowed protocol, SQL Server rejects the connection attempt
    tlsprotocols?: string | *"1.2,1.3"
    // Path to the Kerberos keytab file
    kerberoskeytabfile?: string | *"/etc/krb5.keytab"
    // The name of the Kerberos principal
    privilegedadaccount?: string | *"administrator"
    // Enable looking up KDC information from krb5.conf. Values can be true or false.
    enablekdcfromkrb5conf?: bool | *true
    // whether to enable kerberos
    enablekerberos?: bool | *true
    // hostname of SQL Server
    hostname?: string | *"sqlserver.example.com"
    // The tcpport setting changes the TCP port where SQL Server listens for connections. By default, this port is set to 1433
    tcpport?: int & >=1024 & <=65535 | *1433
}

// Memory section parameters
#MemoryParameters: {
	  // The memorylimitmb setting controls the amount of physical memory (in MB) available to SQL Server. The default is 80% of the physical memory, to prevent out-of-memory (OOM) conditions.
    memorylimitmb?: int & >=512 & <=2147483647 | *8192
    // Sets the maximum percentage of total OS memory that SQL Server can consume.
    systemmemorylimitpercent?: int & >=10 & <=100 | *80
    // Adjusts the percentage of memory a single query can reserve for operations like sorting and hashing.
    query_memory_grant_percent?: int & >=0 & <=100 | *25
}

// File location section parameters
#FileLocationParameters: {
	  // The defaultdatadir change the location where the new database are created
    defaultdatadir?: string | *"/var/opt/mssql/data"
    // The defaultlogdir change the location where the log files are created
    defaultlogdir?: string | *"/var/opt/mssql/log"
    // The defaultdumpdir setting changes the default location where the memory and SQL dumps are generated whenever there's a crash
    defaultdumpdir?: string | *"/var/opt/mssql/dumps"
    // The defaultbackupdir setting changes the default location where the backup files are generated
    defaultbackupdir?: string | *"/var/opt/mssql/backup"
}

// SQL Agent section parameters
#SQLAgentParameters: {
		// whether to enable sql agent
    enabled?: bool | *true
    // errorlogginglevel settings allows you to set the SQL Agent logging level respectively.SQL Agent logging levels are bitmask values that equal: 1 = Errors, 2 = Warnings, 4 = Info, If you want to capture all levels, use 7 as the value
    errorlogginglevel?: int & >=0 & <=7 | *1
    // Determines whether SQL Server waits for all databases to recover before allowing connections during startup.
    startupwaitforalldb?: int & (0 | 1) | *1
}

// Telemetry section parameters
#TelemetryParameters: {
		// The customerfeedback setting changes whether SQL Server sends feedback to Microsoft or not.
    customerfeedback?: bool | *false
    // The userrequestedlocalauditdirectory setting enables Local Audit and lets you set the directory where the Local Audit logs are created.
    userrequestedlocalauditdirectory?: string | *"/var/opt/mssql/audit"
}

// High Availability and Disaster Recovery section parameters
#HADRParameters: {
		// The hadrenabled option enables availability groups on your SQL Server instance
    hadrenabled?: int & (0 | 1) | *1
    // Specifies the TCP port number used by the Always On Availability Group endpoint for replication traffic.
    hadrendpointport?: int & >=1024 & <=65535 | *5022
    // Defines the name of the Always On Availability Group endpoint for high-availability communication.
    hadrendpointname?: string | *"Hadr_endpoint"
}

// Trace flags section parameters
#TraceFlagParameters: {
		// The traceflag option enables or disables trace flags for the startup of the SQL Server service
    traceflag0?: int | *1117  // Grow all files in a filegroup equally
    // The traceflag option enables or disables trace flags for the startup of the SQL Server service
    traceflag1?: int | *1118  // Reduce SGAM contention
    // The traceflag option enables or disables trace flags for the startup of the SQL Server service
    traceflag2?: int | *3226  // Suppress successful backup messages in error log
    // The traceflag option enables or disables trace flags for the startup of the SQL Server service
    traceflag3?: int | *4199  // Enable query optimizer fixes
}

// Language section parameters
#LanguageParameters: {
		// The lcid setting changes the SQL Server locale to any supported language identifier (LCID).
    lcid?: int | *1033  // English (US)
}

// Backup section parameters
#BackupParameters: {
		// Determines whether data compression is enabled by default for new tables and indexes.
    compressiondefault?: int & (0 | 1) | *1
    // Specifies the number of memory buffers allocated for SQL Server backup or restore operations.
    buffercount?: int & >=1 & <=100 | *50
    // Defines the maximum I/O transfer size (in bytes) for backup, restore, and database operations.
    maxtransfersize?: int & >=65536 & <=4194304 | *4194304
    // Sets the physical block size (in bytes) for backup media, affecting storage efficiency and performance.
    blocksize?: int & >=512 & <=65536 | *65536
}

// Distributed transaction section parameters
#DistributedTransactionParameters: {
		// MSDTC rpc server port
    servertcpport?: int & >=1024 & <=65535 | *51000
    // Whether to enable xtp
    enablextp?: bool | *true
}

// Logging section parameters
#LoggingParameters: {
		// Path to error log file
    errorlogfile?: string | *"/var/opt/mssql/log/errorlog"
		// Defines the number of days SQL Server retains error log files before automatic deletion.
    errorlogretentiondays?: int & >=1 & <=365 | *30
    // Sets the maximum size (in KB) for each SQL Server error log file before rotation occurs.
    errorlogsizeinkb?: int & >=1024 & <=102400 | *102400
}

// Resource Governor section parameters
#ResourceGovernorParameters: {
		// Whether to enable resource governor
    enabled?: bool | *true
    // Sets the maximum time (in seconds) for classifying a connection request before it times out in SQL Server Resource Governor.
    classificationtimeout?: int & >=1000 & <=60000 | *30000
}

// Auditing section parameters
#AuditingParameters: {
		// Whether to enable audit
    enabled?: bool | *true
    // Sets the maximum size for each SQL Server audit file before rotation occurs.
    logsize?: int & >=1024 & <=102400 | *102400
    // Path to audit file
    filepath?: string | *"/var/opt/mssql/audit"
    // Defines the number of days SQL Server retains audit files before automatic deletion.
    retention?: int & >=1 & <=365 | *30
}

// Contained Database section parameters
#ContainedDatabaseParameters: {
		// Whether to enable Contained Database
    enabled?: bool | *true
}

// Cross-database ownership chaining section parameters
#CrossDBOwnershipParameters: {
		// Whether to enable Cross-database ownership
    enabled?: bool | *false
}

// Main MSSQL Parameters configuration that includes all sections
#MSSQLParameters: {
    eula: #EULAParameters
    coredump: #CoredumpParameters
    network: #NetworkParameters
    memory: #MemoryParameters
    filelocation: #FileLocationParameters
    sqlagent: #SQLAgentParameters
    telemetry: #TelemetryParameters
    hadr: #HADRParameters
    traceflag: #TraceFlagParameters
    language: #LanguageParameters
    backup: #BackupParameters
    distributedtransaction: #DistributedTransactionParameters
    logging: #LoggingParameters
    resourcegovernor: #ResourceGovernorParameters
    auditing: #AuditingParameters
    containeddatabase: #ContainedDatabaseParameters
    crossdbownership: #CrossDBOwnershipParameters
}

configuration: #MSSQLParameters & {
}
