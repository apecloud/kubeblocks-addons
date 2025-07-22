#TIDBParameter: {
	// Determines whether to create a separate Region for each table. It is recommended to set it to `false` if you need to create a large number of tables (for example, more than 100 thousand tables).
	"split-table": bool | *true

	// Controls the maximum cached chunk objects of chunk allocation. Setting this configuration item to too large a value might increase the risk of OOM.
	"tidb-max-reuse-chunk": float & >=0 & <=2.147483648e+09 | *64

	// Controls the maximum cached column objects of chunk allocation. Setting this configuration item to too large a value might increase the risk of OOM.
	"tidb-max-reuse-column": float & >=0 & <=2.147483648e+09 | *256

	// The number of sessions that can execute requests concurrently. Type: Integer. Maximum Value (64-bit platforms): `18446744073709551615`. Maximum Value (32-bit platforms): `4294967295`
	"token-limit": float & >=1 | *1000

	// File system location used by TiDB to store temporary data. If a feature requires local storage in TiDB nodes, TiDB stores the corresponding temporary data in this location. When creating an index, if [`tidb_ddl_enable_fast_reorg`](/system-variables.md#tidb_ddl_enable_fast_reorg-new-in-v630) is enabled, data that needs to be backfilled for a newly created index will be at first stored in the TiDB local temporary directory, and then imported into TiKV in batches, thus accelerating the index creation. When [`IMPORT INTO`](/sql-statements/sql-statement-import-into.md) is used to import data, the sorted data is first stored in the TiDB local temporary directory, and then imported into TiKV in batches.
	"temp-dir": string | *"/tmp/tidb"

	// Controls whether to enable the temporary storage for some operators when a single SQL statement exceeds the memory quota specified by the system variable [`tidb_mem_quota_query`](/system-variables.md#tidb_mem_quota_query).
	"oom-use-tmp-storage": bool | *true

	// Specifies the temporary storage path for some operators when a single SQL statement exceeds the memory quota specified by the system variable [`tidb_mem_quota_query`](/system-variables.md#tidb_mem_quota_query). This configuration takes effect only when the system variable [`tidb_enable_tmp_storage_on_oom`](/system-variables.md#tidb_enable_tmp_storage_on_oom) is `ON`.
	"tmp-storage-path": string

	// Specifies the quota for the storage in `tmp-storage-path`. The unit is byte. When a single SQL statement uses a temporary disk and the total volume of the temporary disk of the TiDB server exceeds this configuration value, the current SQL operation is cancelled and the `Out of Global Storage Quota!` error is returned. When the value of this configuration is smaller than `0`, the above check and limit do not apply. When the remaining available storage in `tmp-storage-path` is lower than the value defined by `tmp-storage-quota`, the TiDB server reports an error when it is started, and exits.
	"tmp-storage-quota": int | *-1

	// The timeout of the DDL lease. Unit: second
	"lease": string | *"45s"

	// Determines whether to set the `KILL` statement to be MySQL compatible. `compatible-kill-query` takes effect only when [`enable-global-kill`](#enable-global-kill-new-in-v610) is set to `false`. When [`enable-global-kill`](#enable-global-kill-new-in-v610) is `false`, `compatible-kill-query` controls whether you need to append the `TIDB` keyword when killing a query.When `compatible-kill-query` is `false`, the behavior of `KILL xxx` in TiDB is different from that in MySQL. To kill a query in TiDB, you need to append the `TIDB` keyword, such as `KILL TIDB xxx`.When `compatible-kill-query` is `true`, to kill a query in TiDB, there is no need to append the `TIDB` keyword. It is **STRONGLY NOT RECOMMENDED** to set `compatible-kill-query` to `true` in your configuration file UNLESS you are certain that clients will be always connected to the same TiDB instance. This is because pressing <kbd>Control</kbd>+<kbd>C</kbd> in the default MySQL client opens a new connection in which `KILL` is executed. If there is a proxy between the client and the TiDB cluster, the new connection might be routed to a different TiDB instance, which possibly kills a different session by mistake. When [`enable-global-kill`](#enable-global-kill-new-in-v610) is `true`, `KILL xxx` and `KILL TIDB xxx` have the same effect. For more information about the `KILL` statement, see [KILL [TIDB]](/sql-statements/sql-statement-kill.md).
	"compatible-kill-query": bool | *false

	// Determines whether to enable the `utf8mb4` character check. When this feature is enabled, if the character set is `utf8` and the `mb4` characters are inserted in `utf8`, an error is returned. Since v6.1.0, whether to enable the `utf8mb4` character check is determined by the TiDB configuration item `instance.tidb_check_mb4_value_in_utf8` or the system variable `tidb_check_mb4_value_in_utf8`. `check-mb4-value-in-utf8` still takes effect. But if both `check-mb4-value-in-utf8` and `instance.tidb_check_mb4_value_in_utf8` are set, the latter takes effect.
	"check-mb4-value-in-utf8": bool | *false

	// Determines whether to treat the `utf8` character set in old tables as `utf8mb4`.
	"treat-old-version-utf8-as-utf8mb4": bool | *true

	// Determines whether to add or remove the primary key constraint to or from a column. With this default setting, adding or removing the primary key constraint is not supported. You can enable this feature by setting `alter-primary-key` to `true`. However, if a table already exists before the switch is on, and the data type of its primary key column is an integer, dropping the primary key from the column is not possible even if you set this configuration item to `true`.
	"alter-primary-key": bool | *false

	// Modifies the version string returned by TiDB in the following situations:When the built-in `VERSION()` function is used.When TiDB establishes the initial connection to the client and returns the initial handshake packet with version string of the server. For details, see [MySQL Initial Handshake Packet](https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_connection_phase.html#sect_protocol_connection_phase_initial_handshake). By default, the format of the TiDB version string is `5.7.${mysql_latest_minor_version}-TiDB-${tidb_version}`.
	"server-version": string

	// Determines whether to enable the untrusted repair mode. When the `repair-mode` is set to `true`, bad tables in the `repair-table-list` cannot be loaded. The `repair` syntax is not supported by default. This means that all tables are loaded when TiDB is started.
	"repair-mode": bool | *false

	// `repair-table-list` is only valid when [`repair-mode`](#repair-mode) is set to `true`. `repair-table-list` is a list of bad tables that need to be repaired in an instance. An example of the list is: ["db.table1","db.table2"...]. The list is empty by default. This means that there are no bad tables that need to be repaired.
	"repair-table-list": [...string] | *[]

	// Enables or disables the new collation support. Note: This configuration takes effect only for the TiDB cluster that is first initialized. After the initialization, you cannot use this configuration item to enable or disable the new collation support.
	"new_collations_enabled_on_first_bootstrap": bool | *true

	// The maximum number of concurrent client connections allowed in TiDB. It is used to control resources. By default, TiDB does not set limit on the number of concurrent client connections. When the value of this configuration item is greater than `0` and the number of actual client connections reaches this value, the TiDB server rejects new client connections. Since v6.2.0, the TiDB configuration item [`instance.max_connections`](/tidb-configuration-file.md#max_connections) or the system variable [`max_connections`](/system-variables.md#max_connections) is used to set the maximum number of concurrent client connections allowed in TiDB. `max-server-connections` still takes effect. But if `max-server-connections` and `instance.max_connections` are set at the same time, the latter takes effect.
	"max-server-connections": int | *0

	// Sets the maximum allowable length of the newly created index. Unit: byte. Currently, the valid value range is `[3072, 3072*4]`. MySQL and TiDB (version < v3.0.11) do not have this configuration item, but both limit the length of the newly created index. This limit in MySQL is `3072`. In TiDB (version =< 3.0.7), this limit is `3072*4`. In TiDB (3.0.7 < version < 3.0.11), this limit is `3072`. This configuration is added to be compatible with MySQL and earlier versions of TiDB.
	"max-index-length": int | *3072

	// Sets the limit on the number of columns in a single table. Currently, the valid value range is `[1017, 4096]`.
	"table-column-count-limit": int | *1017

	// Sets the limit on the number of indexes in a single table. Currently, the valid value range is `[64, 512]`.
	"index-limit": int | *64

	// Enables or disables the telemetry collection in TiDB. When this configuration is set to `true` on a TiDB instance, the telemetry collection in this TiDB instance is enabled and the [`tidb_enable_telemetry`](/system-variables.md#tidb_enable_telemetry-new-in-v402) system variable takes effect. When this configuration is set to `false` on all TiDB instances, the telemetry collection in TiDB is disabled and the [`tidb_enable_telemetry`](/system-variables.md#tidb_enable_telemetry-new-in-v402) system variable does not take effect. See [Telemetry](/telemetry.md) for details.
	"enable-telemetry": bool | *false

	// Deprecates the display width for integer types when this configuration item is set to `true`.
	"deprecate-integer-display-length": bool | *false

	// Enables or disables listening on TCP4 only. Enabling this option is useful when TiDB is used with LVS for load balancing because the [real client IP from the TCP header](https://github.com/alibaba/LVS/tree/master/kernel/net/toa) can be correctly parsed by the "tcp4" protocol.
	"enable-tcp4-only": bool | *false

	// Determines whether to limit the maximum length of a single `ENUM` element and a single `SET` element. When this configuration value is `true`, the maximum length of a single `ENUM` element and a single `SET` element is 255 characters, which is compatible with [MySQL 8.0](https://dev.mysql.com/doc/refman/8.0/en/string-type-syntax.html). When this configuration value is `false`, there is no limit on the length of a single element, which is compatible with TiDB (earlier than v5.0).
	"enable-enum-length-limit": bool | *true

	// Specifies the number of seconds that TiDB waits when you shut down the server, which allows the clients to disconnect. When TiDB is waiting for shutdown (in the grace period), the HTTP status will indicate a failure, which allows the load balancers to reroute traffic.
	"graceful-wait-before-shutdown": int | *0

	// Controls whether to enable the Global Kill (terminating queries or connections across instances) feature. When the value is `true`, both `KILL` and `KILL TIDB` statements can terminate queries or connections across instances so you do not need to worry about erroneously terminating queries or connections. When you use a client to connect to any TiDB instance and execute the `KILL` or `KILL TIDB` statement, the statement will be forwarded to the target TiDB instance. If there is a proxy between the client and the TiDB cluster, the `KILL` and `KILL TIDB` statements will also be forwarded to the target TiDB instance for execution. Starting from v7.3.0, you can terminate a query or connection using the MySQL command line <kbd>Control+C</kbd> when both `enable-global-kill` and [`enable-32bits-connection-id`](#enable-32bits-connection-id-new-in-v730) are set to `true`. For more information, see [`KILL`](/sql-statements/sql-statement-kill.md).
	"enable-global-kill": bool | *true

	// Controls whether to enable the 32-bit connection ID feature. When both this configuration item and [`enable-global-kill`](#enable-global-kill-new-in-v610) are set to `true`, TiDB generates 32-bit connection IDs. This enables you to terminate queries or connections by the MySQL command-line <kbd>Control+C</kbd>.
	"enable-32bits-connection-id": bool | *true

	// Specifies the SQL script to be executed when the TiDB cluster is started for the first time. All SQL statements in this script are executed with the highest privilege without any privilege check. If the specified SQL script fails to execute, the TiDB cluster might fail to start. This configuration item is used to perform such operations as modifying the value of a system variable, creating a user, or granting privileges.
	"initialize-sql-file": string

	// Controls whether the PD client and TiKV client in TiDB forward requests to the leader via the followers in the case of possible network isolation. If the environment might have isolated network, enabling this parameter can reduce the window of service unavailability. If you cannot accurately determine whether isolation, network interruption, or downtime has occurred, using this mechanism has the risk of misjudgment and causes reduced availability and performance. If network failure has never occurred, it is not recommended to enable this parameter.
	"enable-forwarding": bool | *false

	// Controls whether to enable the table lock feature. The table lock is used to coordinate concurrent access to the same table among multiple sessions. Currently, the `READ`, `WRITE`, and `WRITE LOCAL` lock types are supported. When the configuration item is set to `false`, executing the `LOCK TABLES` or `UNLOCK TABLES` statement does not take effect and returns the "LOCK/UNLOCK TABLES is not supported" warning. For more information, see [`LOCK TABLES` and `UNLOCK TABLES`](/sql-statements/sql-statement-lock-tables-and-unlock-tables.md).
	"enable-table-lock": bool | *false

	// Specify server labels. For example, `{ zone = "us-west-1", dc = "dc1", rack = "rack1", host = "tidb1" }`.
	"labels": string | *"{}"

	// Specifies the log output level. Value options: `debug`, `info`, `warn`, `error`, and `fatal`.
	"log.level": string | *"info"

	// Specifies the log output format. Value options: `json` and `text`.
	"log.format": string | *"text"

	// Determines whether to enable timestamp output in the log. If you set the value to `false`, the log does not output timestamp.
	"log.enable-timestamp": bool | *false

	// Determines whether to enable the slow query log. To enable the slow query log, set `enable-slow-log` to `true`. Otherwise, set it to `false`. Since v6.1.0, whether to enable slow query log is determined by the TiDB configuration item [`instance.tidb_enable_slow_log`](/tidb-configuration-file.md#tidb_enable_slow_log) or the system variable [`tidb_enable_slow_log`](/system-variables.md#tidb_enable_slow_log). `enable-slow-log` still takes effect. But if `enable-slow-log` and `instance.tidb_enable_slow_log` are set at the same time, the latter takes effect.
	"log.enable-slow-log": bool | *true

	// The file name of the slow query log. The format of the slow log is updated in TiDB v2.1.8, so the slow log is output to the slow log file separately. In versions before v2.1.8, this variable is set to "" by default. After you set it, the slow query log is output to this file separately.
	"log.slow-query-file": string | *"tidb-slow.log"

	// Outputs the threshold value of consumed time in the slow log. Unit: Milliseconds. When the time consumed by a query is larger than this value, this query is considered as a slow query and its log is output to the slow query log. Note that when the output level of [`log.level`](#level) is `"debug"`, all queries are recorded in the slow query log, regardless of the setting of this parameter. Since v6.1.0, the threshold value of consumed time in the slow log is specified by the TiDB configuration item [`instance.tidb_slow_log_threshold`](/tidb-configuration-file.md#tidb_slow_log_threshold) or the system variable [`tidb_slow_log_threshold`](/system-variables.md#tidb_slow_log_threshold). `slow-threshold` still takes effect. But if `slow-threshold` and `instance.tidb_slow_log_threshold` are set at the same time, the latter takes effect.
	"log.slow-threshold": int | *300

	// Determines whether to record execution plans in the slow log. Since v6.1.0, whether to record execution plans in the slow log is determined by the TiDB configuration item [`instance.tidb_record_plan_in_slow_log`](/tidb-configuration-file.md#tidb_record_plan_in_slow_log) or the system variable [`tidb_record_plan_in_slow_log`](/system-variables.md#tidb_record_plan_in_slow_log). `record-plan-in-slow-log` still takes effect. But if `record-plan-in-slow-log` and `instance.tidb_record_plan_in_slow_log` are set at the same time, the latter takes effect.
	"log.record-plan-in-slow-log": int | *1

	// Outputs the threshold value of the number of rows for the `expensive` operation. When the number of query rows (including the intermediate results based on statistics) is larger than this value, it is an `expensive` operation and outputs log with the `[EXPENSIVE_QUERY]` prefix.
	"log.expensive-threshold": int | *10000

	// Sets the timeout for log-writing operations in TiDB. In case of a disk failure that prevents logs from being written, this configuration item can trigger the TiDB process to panic instead of hang. Unit: second. In some user scenarios, TiDB logs might be stored on hot-pluggable or network-attached disks, which might become permanently unavailable. In these cases, TiDB cannot recover automatically from such disaster and the log-writing operations will be permanently blocked. Although the TiDB process might seem to be running, it does not respond to any requests. This configuration item is designed to handle such situations. Default value: 0, indicating no timeout is set.
	"log.timeout": int | *0

	// Enables the Security Enhanced Mode (SEM). The status of SEM is available via the system variable [`tidb_enable_enhanced_security`](/system-variables.md#tidb_enable_enhanced_security).
	"security.enable-sem": bool | *false

	// The file path of the trusted CA certificate in the PEM format. If you set this option and `--ssl-cert`, `--ssl-key` at the same time, TiDB authenticates the client certificate based on the list of trusted CAs specified by this option when the client presents the certificate. If the authentication fails, the connection is terminated. If you set this option but the client does not present the certificate, the secure connection continues without client certificate authentication.
	"security.ssl-ca": string

	// The file path of the SSL certificate in the PEM format. If you set this option and `--ssl-key` at the same time, TiDB allows (but not forces) the client to securely connect to TiDB using TLS. If the specified certificate or private key is invalid, TiDB starts as usual but cannot receive secure connection.
	"security.ssl-cert": string

	// The file path of the SSL certificate key in the PEM format, that is, the private key of the certificate specified by `--ssl-cert`. Currently, TiDB does not support loading the private keys protected by passwords.
	"security.ssl-key": string

	// The CA root certificate used to connect TiKV or PD with TLS.
	"security.cluster-ssl-ca": string

	// The path of the SSL certificate file used to connect TiKV or PD with TLS.
	"security.cluster-ssl-cert": string

	// The path of the SSL private key file used to connect TiKV or PD with TLS.
	"security.cluster-ssl-key": string

	// A list of acceptable X.509 Common Names in certificates presented by clients. Requests are permitted only when the presented Common Name is an exact match with one of the entries in the list.
	"security.cluster-verify-cn": [...string] | *[]

	// Determines the encryption method used for saving the spilled files to disk. Optional values: `"plaintext"` and `"aes128-ctr"`
	"security.spilled-file-encryption-method": string | *"plaintext"

	// Determines whether to automatically generate the TLS certificates on startup.
	"security.auto-tls": bool | *false

	// Set the minimum TLS version for MySQL Protocol connections. Optional values: `"TLSv1.0"`, `"TLSv1.1"`, `"TLSv1.2"` and `"TLSv1.3"`
	"security.tls-version": string | *", which allows TLSv1.1 or higher."

	// Set the local file path of the JSON Web Key Sets (JWKS) for the [`tidb_auth_token`](/security-compatibility-with-mysql.md#tidb_auth_token) authentication method.
	"security.auth-token-jwks": string

	// Set the JWKS refresh interval for the [`tidb_auth_token`](/security-compatibility-with-mysql.md#tidb_auth_token) authentication method.
	"security.auth-token-refresh-interval": string | *"1h"

	// Determines whether TiDB disconnects the client connection when the password is expired. Optional values: `true`, `false`. If you set it to `true`, the client connection is disconnected when the password is expired. If you set it to `false`, the client connection is restricted to the "sandbox mode" and the user can only execute the password reset operation.
	"security.disconnect-on-expired-password": bool | *true

	// The certificate file path, which is used by [TiProxy](https://docs.pingcap.com/tidb/stable/tiproxy-overview) for session migration. Empty value will cause TiProxy session migration to fail. To enable session migration, all TiDB nodes must set this to the same certificate and key. This means that you should store the same certificate and key on every TiDB node.
	"security.session-token-signing-cert": string

	// The key file path used by [TiProxy](https://docs.pingcap.com/tidb/stable/tiproxy-overview) for session migration. Refer to the descriptions of [`session-token-signing-cert`](#session-token-signing-cert-new-in-v640).
	"security.session-token-signing-key": string

	// The number of CPUs used by TiDB. The default `0` indicates using all the CPUs on the machine. You can also set it to n, and then TiDB uses n CPUs. The default 0 indicates using all the CPUs on the machine. You can also set it to n, and then TiDB uses n CPUs.
	"performance.max-procs": int | *0

	// The longest time that a single transaction can hold locks. If this time is exceeded, the locks of a transaction might be cleared by other transactions so that this transaction cannot be successfully committed. Unit: Millisecond. The transaction that holds locks longer than this time can only be committed or rolled back. The commit might not be successful.
	"performance.max-txn-ttl": int | *3600000

	// The maximum number of statements allowed in a single TiDB transaction. If a transaction does not roll back or commit after the number of statements exceeds `stmt-count-limit`, TiDB returns the `statement count 5001 exceeds the transaction limitation, autocommit = false` error. This configuration takes effect **only** in the retryable optimistic transaction. If you use the pessimistic transaction or have disabled the transaction retry, the number of statements in a transaction is not limited by this configuration.
	"performance.stmt-count-limit": int | *5000

	// The size limit of a single row of data in TiDB. The unit is in bytes. The size limit of a single key-value record in a transaction. If the size limit is exceeded, TiDB returns the `entry too large` error. The maximum value of this configuration item does not exceed `125829120` (120 MB). Note that TiKV has a similar limit. If the data size of a single write request exceeds [`raft-entry-max-size`](/tikv-configuration-file.md#raft-entry-max-size), which is 8 MB by default, TiKV refuses to process this request. When a table has a row of large size, you need to modify both configurations at the same time. The default value of [`max_allowed_packet`](/system-variables.md#max_allowed_packet-new-in-v610) (the maximum size of a packet for the MySQL protocol) is 67108864 (64 MiB). If a row is larger than `max_allowed_packet`, the row gets truncated. The default value of [`txn-total-size-limit`](#txn-total-size-limit) (the size limit of a single transaction in TiDB) is 100 MiB. If you increase the `txn-entry-size-limit` value to be over 100 MiB, you need to increase the `txn-total-size-limit` value accordingly.
	"performance.txn-entry-size-limit": int | *6291456

	// The size limit of a single transaction in TiDB. The unit is in bytes. In a single transaction, the total size of key-value records cannot exceed this value. The maximum value of this parameter is `1099511627776` (1 TB). Note that if you have used the binlog to serve the downstream consumer Kafka (such as the `arbiter` cluster), the value of this parameter must be no more than `1073741824` (1 GB). This is because 1 GB is the upper limit of a single message size that Kafka can process. Otherwise, an error is returned if this limit is exceeded. In TiDB v6.5.0 and later versions, this configuration is no longer recommended. The memory size of a transaction will be accumulated into the memory usage of the session, and the [`tidb_mem_quota_query`](/system-variables.md#tidb_mem_quota_query) variable will take effect when the session memory threshold is exceeded. To be compatible with previous versions, this configuration works as follows when you upgrade from an earlier version to TiDB v6.5.0 or later:If this configuration is not set or is set to the default value (`104857600`), after an upgrade, the memory size of a transaction will be accumulated into the memory usage of the session, and the `tidb_mem_quota_query` variable will take effect.If this configuration is not defaulted (`104857600`), it still takes effect and its behavior on controlling the size of a single transaction remains unchanged before and after the upgrade. This means that the memory size of the transaction is not controlled by the `tidb_mem_quota_query` variable.
	"performance.txn-total-size-limit": int | *104857600

	// Determines whether to enable `keepalive` in the TCP layer.
	"performance.tcp-keep-alive": bool | *true

	// Determines whether to enable TCP_NODELAY at the TCP layer. After it is enabled, TiDB disables the Nagle algorithm in the TCP/IP protocol and allows sending small data packets to reduce network latency. This is suitable for latency-sensitive applications with a small transmission volume of data.
	"performance.tcp-no-delay": bool | *true

	// TiDB supports executing the `JOIN` statement without any condition (the `WHERE` field) of both sides tables by default; if you set the value to `false`, the server refuses to execute when such a `JOIN` statement appears.
	"performance.cross-join": bool | *true

	// The time interval of reloading statistics, updating the number of table rows, checking whether it is needed to perform the automatic analysis, using feedback to update statistics and loading statistics of columns. When `stats-lease` is set to 0s, TiDB periodically reads the feedback in the system table, and updates the statistics cached in the memory every three seconds. But TiDB no longer automatically modifies the following statistics-related system tables:`mysql.stats_meta`: TiDB no longer automatically records the number of table rows that are modified by the transaction and updates it to this system table.`mysql.stats_histograms`/`mysql.stats_buckets` and `mysql.stats_top_n`: TiDB no longer automatically analyzes and proactively updates statistics.`mysql.stats_feedback`: TiDB no longer updates the statistics of the tables and indexes according to a part of statistics returned by the queried data.
	"performance.stats-lease": string | *"3s"

	// The ratio of (number of modified rows)/(total number of rows) in a table. If the value is exceeded, the system assumes that the statistics have expired and the pseudo statistics will be used. The minimum value is `0` and the maximum value is `1`.
	"performance.pseudo-estimate-ratio": float & >=0 & <=1 | *0.8

	// Sets the priority for all statements. Value options: The default value `NO_PRIORITY` means that the priority for statements is not forced to change. Other options are `LOW_PRIORITY`, `DELAYED`, and `HIGH_PRIORITY` in ascending order. Since v6.1.0, the priority for all statements is determined by the TiDB configuration item [`instance.tidb_force_priority`](/tidb-configuration-file.md#tidb_force_priority) or the system variable [`tidb_force_priority`](/system-variables.md#tidb_force_priority). `force-priority` still takes effect. But if `force-priority` and `instance.tidb_force_priority` are set at the same time, the latter takes effect.
	"performance.force-priority": string | *"NO_PRIORITY"

	// Determines whether the optimizer executes the operation that pushes down the aggregation function with `Distinct` (such as `select count(distinct a) from t`) to Coprocessors. Default: `false`. This variable is the initial value of the system variable [`tidb_opt_distinct_agg_push_down`](/system-variables.md#tidb_opt_distinct_agg_push_down).
	"performance.distinct-agg-push-down": string

	// Determines whether to ignore the optimizer's cost estimation and to forcibly use TiFlash's MPP mode for query execution. This configuration item controls the initial value of [`tidb_enforce_mpp`](/system-variables.md#tidb_enforce_mpp-new-in-v51). For example, when this configuration item is set to `true`, the default value of `tidb_enforce_mpp` is `ON`.
	"performance.enforce-mpp": bool | *false

	// Controls whether to enable the memory quota for the statistics cache.
	"performance.enable-stats-cache-mem-quota": bool | *true

	// The maximum number of columns that the TiDB synchronously loading statistics feature can process concurrently. Currently, the valid value range is `[1, 128]`.
	"performance.stats-load-concurrency": int | *5

	// The maximum number of column requests that the TiDB synchronously loading statistics feature can cache. Currently, the valid value range is `[1, 100000]`.
	"performance.stats-load-queue-size": int | *1000

	// Controls whether to initialize statistics concurrently during TiDB startup.
	"performance.concurrently-init-stats": bool | *false

	// Controls whether to use lightweight statistics initialization during TiDB startup. When the value of `lite-init-stats` is `true`, statistics initialization does not load any histogram, TopN, or Count-Min Sketch of indexes or columns into memory. When the value of `lite-init-stats` is `false`, statistics initialization loads histograms, TopN, and Count-Min Sketch of indexes and primary keys into memory but does not load any histogram, TopN, or Count-Min Sketch of non-primary key columns into memory. When the optimizer needs the histogram, TopN, and Count-Min Sketch of a specific index or column, the necessary statistics are loaded into memory synchronously or asynchronously (controlled by [`tidb_stats_load_sync_wait`](/system-variables.md#tidb_stats_load_sync_wait-new-in-v540)). Setting `lite-init-stats` to `true` speeds up statistics initialization and reduces TiDB memory usage by avoiding unnecessary statistics loading. For details, see [Load statistics](/statistics.md#load-statistics).
	"performance.lite-init-stats": bool | *true

	// Controls whether to wait for statistics initialization to finish before providing services during TiDB startup. When the value of `force-init-stats` is `true`, TiDB needs to wait until statistics initialization is finished before providing services upon startup. Note that if there are a large number of tables and partitions and the value of [`lite-init-stats`](/tidb-configuration-file.md#lite-init-stats-new-in-v710) is `false`, setting `force-init-stats` to `true` might prolong the time it takes for TiDB to start providing services. When the value of `force-init-stats` is `false`, TiDB can still provide services before statistics initialization is finished, but the optimizer uses pseudo statistics to make decisions, which might result in suboptimal execution plans.
	"performance.force-init-stats": bool | *true

	// Enables opentracing to trace the call overhead of some TiDB components. Note that enabling opentracing causes some performance loss.
	"opentracing.enable": bool | *false

	// Enables RPC metrics.
	"opentracing.rpc-metrics": bool | *false

	// Specifies the type of the opentracing sampler. The string value is case-insensitive. Value options: `"const"`, `"probabilistic"`, `"ratelimiting"`, `"remote"`
	"opentracing.sampler.type": string | *"const"

	// The parameter of the opentracing sampler.For the `const` type, the value can be `0` or `1`, which indicates whether to enable the `const` sampler.For the `probabilistic` type, the parameter specifies the sampling probability, which can be a float number between `0` and `1`.For the `ratelimiting` type, the parameter specifies the number of spans sampled per second.For the `remote` type, the parameter specifies the sampling probability, which can be a float number between `0` and `1`.
	"opentracing.sampler.param": float | *1.0

	// The HTTP URL of the jaeger-agent sampling server.
	"opentracing.sampler.sampling-server-url": string

	// The maximum number of operations that the sampler can trace. If an operation is not traced, the default probabilistic sampler is used.
	"opentracing.sampler.max-operations": int | *0

	// Controls the frequency of polling the jaeger-agent sampling policy.
	"opentracing.sampler.sampling-refresh-interval": int | *0

	// The queue size with which the reporter records spans in memory.
	"opentracing.reporter.queue-size": int | *0

	// The interval at which the reporter flushes the spans in memory to the storage.
	"opentracing.reporter.buffer-flush-interval": int | *0

	// Determines whether to print the log for all submitted spans.
	"opentracing.reporter.log-spans": bool | *false

	// The address at which the reporter sends spans to the jaeger-agent.
	"opentracing.reporter.local-agent-host-port": string

	// The maximum number of connections established with each TiKV.
	"tikv-client.grpc-connection-count": int | *4

	// The `keepalive` time interval of the RPC connection between TiDB and TiKV nodes. If there is no network packet within the specified time interval, the gRPC client executes `ping` command to TiKV to see if it is alive. Default: `10`. Unit: second
	"tikv-client.grpc-keepalive-time": string

	// The timeout of the RPC `keepalive` check between TiDB and TiKV nodes. Unit: second
	"tikv-client.grpc-keepalive-timeout": int | *3

	// Specifies the compression type used for data transfer between TiDB and TiKV nodes. The default value is `"none"`, which means no compression. To enable the gzip compression, set this value to `"gzip"`. Value options: `"none"`, `"gzip"`
	"tikv-client.grpc-compression-type": string | *"none"

	// The maximum timeout when executing a transaction commit. It is required to set this value larger than twice of the Raft election timeout.
	"tikv-client.commit-timeout": string | *"41s"

	// The maximum number of RPC packets sent in batch. If the value is not `0`, the `BatchCommands` API is used to send requests to TiKV, and the RPC latency can be reduced in the case of high concurrency. It is recommended that you do not modify this value.
	"tikv-client.max-batch-size": int | *128

	// Waits for `max-batch-wait-time` to encapsulate the data packets into a large packet in batch and send it to the TiKV node. It is valid only when the value of `tikv-client.max-batch-size` is greater than `0`. It is recommended not to modify this value. Unit: nanoseconds
	"tikv-client.max-batch-wait-time": int | *0

	// The maximum number of packets sent to TiKV in batch. It is recommended not to modify this value. If the value is `0`, this feature is disabled.
	"tikv-client.batch-wait-size": int | *8

	// The threshold of the TiKV load. If the TiKV load exceeds this threshold, more `batch` packets are collected to relieve the pressure of TiKV. It is valid only when the value of `tikv-client.max-batch-size` is greater than `0`. It is recommended not to modify this value.
	"tikv-client.overload-threshold": int | *200

	// The timeout of a single Coprocessor request. Unit: second
	"tikv-client.copr-req-timeout": int | *60

	// The total size of the cached data. When the cache space is full, old cache entries are evicted. When the value is `0.0`, the Coprocessor Cache feature is disabled. Unit: MB. Type: Float
	"tikv-client.copr-cache.capacity-mb": float | *1000.0

	// Determines whether to enable the memory lock of transactions.
	"txn-local-latches.enabled": bool | *false

	// The number of slots corresponding to Hash, which automatically adjusts upward to an exponential multiple of 2. Each slot occupies 32 Bytes of memory. If set too small, it might result in slower running speed and poor performance in the scenario where data writing covers a relatively large range (such as importing data).
	"txn-local-latches.capacity": int | *2048000

	// Enables or disables binlog.
	"binlog.enable": bool | *false

	// The timeout of writing binlog into Pump. It is not recommended to modify this value. Default: `15s`. unit: second
	"binlog.write-timeout": string

	// Determines whether to ignore errors occurred in the process of writing binlog into Pump. It is not recommended to modify this value. When the value is set to `true` and an error occurs, TiDB stops writing binlog and add `1` to the count of the `tidb_server_critical_error_total` monitoring item. When the value is set to `false`, the binlog writing fails and the entire TiDB service is stopped.
	"binlog.ignore-error": bool | *false

	// The network address to which binlog is exported.
	"binlog.binlog-socket": string

	// The strategy of Pump selection when binlog is exported. Currently, only the `hash` and `range` methods are supported.
	"binlog.strategy": string | *"range"

	// Enables or disables the HTTP API service.
	"status.report-status": bool | *true

	// Determines whether to transmit the database-related QPS metrics to Prometheus.
	"status.record-db-qps": bool | *false

	// Determines whether to transmit the database-related QPS metrics to Prometheus. Supports more metircs types than `record-db-qps`, for example, duration and statements.
	"status.record-db-label": bool | *false

	// The maximum number of retries of each statement in pessimistic transactions. If the number of retries exceeds this limit, an error occurs.
	"pessimistic-txn.max-retry-count": int | *256

	// The maximum number of deadlock events that can be recorded in the [`INFORMATION_SCHEMA.DEADLOCKS`](/information-schema/information-schema-deadlocks.md) table of a single TiDB server. If this table is in full volume and an additional deadlock event occurs, the earliest record in the table will be removed to make place for the newest error.
	"pessimistic-txn.deadlock-history-capacity": int & >=0 & <=10000 | *10

	// Controls whether the [`INFORMATION_SCHEMA.DEADLOCKS`](/information-schema/information-schema-deadlocks.md) table collects the information of retryable deadlock errors. For the description of retryable deadlock errors, see [Retryable deadlock errors](/information-schema/information-schema-deadlocks.md#retryable-deadlock-errors).
	"pessimistic-txn.deadlock-history-collect-retryable": bool | *false

	// Determines the transaction mode that the auto-commit transaction uses when the pessimistic transaction mode is globally enabled (`tidb_txn_mode='pessimistic'`). By default, even if the pessimistic transaction mode is globally enabled, the auto-commit transaction still uses the optimistic transaction mode. After enabling `pessimistic-auto-commit` (set to `true`), the auto-commit transaction also uses pessimistic mode, which is consistent with the other explicitly committed pessimistic transactions. For scenarios with conflicts, after enabling this configuration, TiDB includes auto-commit transactions into the global lock-waiting management, which avoids deadlocks and mitigates the latency spike brought by deadlock-causing conflicts. For scenarios with no conflicts, if there are many auto-commit transactions (the specific number is determined by the real scenarios. For example, the number of auto-commit transactions accounts for more than half of the total number of applications), and a single transaction operates a large data volume, enabling this configuration causes performance regression. For example, the auto-commit `INSERT INTO SELECT` statement.
	"pessimistic-txn.pessimistic-auto-commit": bool | *false

	// Controls the default value of the system variable [`tidb_constraint_check_in_place_pessimistic`](/system-variables.md#tidb_constraint_check_in_place_pessimistic-new-in-v630).
	"pessimistic-txn.constraint-check-in-place-pessimistic": bool | *true

	// Controls from which engine TiDB allows to read data. Value options: Any combinations of "tikv", "tiflash", and "tidb", for example, ["tikv", "tidb"] or ["tiflash", "tidb"]
	"isolation-read.engines": string | *'["tikv", "tiflash", "tidb"]'

	// This configuration controls whether to record the execution information of each operator in the slow query log. Before v6.1.0, this configuration is set by `enable-collect-execution-info`.
	"instance.tidb_enable_collect_execution_info": bool | *true

	// This configuration is used to control whether to enable the slow log feature. Value options: `true` or `false`. Before v6.1.0, this configuration is set by `enable-slow-log`.
	"instance.tidb_enable_slow_log": bool | *true

	// Outputs the threshold value of the time consumed by the slow log. Range: `[-1, 9223372036854775807]`. Unit: Milliseconds. When the time consumed by a query is larger than this value, this query is considered as a slow query and its log is output to the slow query log. Note that when the output level of [`log.level`](#level) is `"debug"`, all queries are recorded in the slow query log, regardless of the setting of this parameter. Before v6.1.0, this configuration is set by `slow-threshold`.
	"instance.tidb_slow_log_threshold": int | *300

	// The configuration controls the number of slowest queries that are cached in memory.
	"instance.in-mem-slow-query-topn-num": int | *30

	// The configuration controls the number of recently used slow queries that are cached in memory.
	"instance.in-mem-slow-query-recent-num": int | *500

	// This configuration is used to set the threshold value that determines whether to print expensive query logs. The difference between expensive query logs and slow query logs is:Slow logs are printed after the statement is executed.Expensive query logs print the statements that are being executed, with execution time exceeding the threshold value, and their related information. Range: `[10, 2147483647]`. Unit: Seconds. Before v5.4.0, this configuration is set by `expensive-threshold`.
	"instance.tidb_expensive_query_time_threshold": int | *60

	// This configuration is used to control whether to include the execution plan of slow queries in the slow log. Value options: `1` (enabled, default) or `0` (disabled). The value of this configuration will initialize the value of system variable [`tidb_record_plan_in_slow_log`](/system-variables.md#tidb_record_plan_in_slow_log). Before v6.1.0, this configuration is set by `record-plan-in-slow-log`.
	"instance.tidb_record_plan_in_slow_log": int | *1

	// This configuration is used to change the default priority for statements executed on a TiDB server. The default value `NO_PRIORITY` means that the priority for statements is not forced to change. Other options are `LOW_PRIORITY`, `DELAYED`, and `HIGH_PRIORITY` in ascending order. Before v6.1.0, this configuration is set by `force-priority`.
	"instance.tidb_force_priority": string | *"NO_PRIORITY"

	// The maximum number of connections permitted for a single TiDB instance. It can be used for resources control. Range: `[0, 100000]`. The default value `0` means no limit. When the value of this variable is larger than `0`, and the number of connections reaches the value, the TiDB server will reject new connections from clients. The value of this configuration will initialize the value of system variable [`max_connections`](/system-variables.md#max_connections). Before v6.2.0, this configuration is set by `max-server-connections`.
	"instance.max_connections": int | *0

	// This configuration controls whether the corresponding TiDB instance can become a DDL owner or not. Possible values: `OFF`, `ON`. The value of this configuration will initialize the value of the system variable [`tidb_enable_ddl`](/system-variables.md#tidb_enable_ddl-new-in-v630). Before v6.3.0, this configuration is set by `run-ddl`.
	"instance.tidb_enable_ddl": bool | *true

	// Controls whether to enable statements summary persistence. For more details, see [Persist statements summary](/statement-summary-tables.md#persist-statements-summary).
	"instance.tidb_stmt_summary_enable_persistent": bool | *false

	// When statements summary persistence is enabled, this configuration specifies the file to which persistent data is written.
	"instance.tidb_stmt_summary_filename": string | *"tidb-statements.log"

	// When statements summary persistence is enabled, this configuration specifies the maximum number of days to keep persistent data files. Unit: day. You can adjust the value based on the data retention requirements and disk space usage.
	"instance.tidb_stmt_summary_file_max_days": int | *3

	// When statements summary persistence is enabled, this configuration specifies the maximum size of a persistent data file. Unit: MiB. You can adjust the value based on the data retention requirements and disk space usage.
	"instance.tidb_stmt_summary_file_max_size": int | *64

	// When statements summary persistence is enabled, this configuration specifies the maximum number of data files that can be persisted. `0` means no limit on the number of files. You can adjust the value based on the data retention requirements and disk space usage.
	"instance.tidb_stmt_summary_file_max_backups": int | *0

	// The list of proxy server's IP addresses allowed to connect to TiDB using the [PROXY protocol](https://www.haproxy.org/download/1.8/doc/proxy-protocol.txt). In general cases, when you access TiDB behind a reverse proxy, TiDB takes the IP address of the reverse proxy server as the IP address of the client. By enabling the PROXY protocol, reverse proxies that support this protocol, such as HAProxy, can pass the real client IP address to TiDB. After configuring this parameter, TiDB allows the configured source IP address to connect to TiDB using the PROXY protocol; if a protocol other than PROXY is used, this connection will be denied. If this parameter is left empty, no IP address can connect to TiDB using the PROXY protocol. The value can be an IP address (192.168.1.50) or CIDR (192.168.1.0/24) with `,` as the separator. `*` means any IP addresses.
	"proxy-protocol.networks": string

	// Controls whether to enable the PROXY protocol fallback mode. If this configuration item is set to `true`, TiDB can accept clients that belong to `proxy-protocol.networks` to connect to TiDB without using the PROXY protocol specification or without sending the PROXY protocol header. By default, TiDB only accepts client connections that belong to `proxy-protocol.networks` and send a PROXY protocol header.
	"proxy-protocol.fallbackable": bool | *false

	// Controls whether an expression index can be created. Since TiDB v5.2.0, if the function in an expression is safe, you can create an expression index directly based on this function without enabling this configuration. If you want to create an expression index based on other functions, you can enable this configuration, but correctness issues might exist. By querying the `tidb_allow_function_for_expression_index` variable, you can get the functions that are safe to be directly used for creating an expression.
	"experimental.allow-expression-index": bool | *false

	...
}

configuration: #TIDBParameter & {}
