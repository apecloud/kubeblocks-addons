//Copyright (C) 2022-2023 ApeCloud Co., Ltd
//
//This file is part of KubeBlocks project
//
//This program is free software: you can redistribute it and/or modify
//it under the terms of the GNU Affero General Public License as published by
//the Free Software Foundation, either version 3 of the License, or
//(at your option) any later version.
//
//This program is distributed in the hope that it will be useful
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU Affero General Public License for more details.
//
//You should have received a copy of the GNU Affero General Public License
//along with this program.  If not, see <http://www.gnu.org/licenses/>.

#NebulaGraphdParameter: {
    // Whether to run as a daemon process.
    "--daemonize": bool | *true

    // File path to store the process ID (PID).
    "--pid_file": string | *"pids/nebula-graphd.pid"

    // Whether to enable the query optimizer.
    "--enable_optimizer": bool | *true

    // Time zone name, e.g., UTC+08:00 for China Standard Time.
    // Format reference: https://www.gnu.org/software/libc/manual/html_node/TZ-Variable.html
    // Default value: UTC+00:00:00 if not specified.
    "--timezone_name": string | *"UTC+00:00:00"

    // Default character set when creating graph spaces.
    "--default_charset": string | *"utf8"

    // Default collation when creating graph spaces.
    "--default_collate": string | *"utf8_bin"

    // Whether to load configuration from local config file.
    "--local_config": bool | *true

    // Directory to store Graph service logs.
	// It is recommended to place logs and data on different disks.
	"--log_dir": string | *"logs"

	// Minimum log level to record (INFO=0, WARNING=1, ERROR=2, FATAL=3).
	// Setting to 4 disables all logs.
	// Suggested values:
	//   - 0 (INFO) for debugging
	//   - 1 (WARNING) for production
	// dynamic: true
	"--minloglevel": int & >=0 & <=4 | *0

	// VLOG verbosity level. Records VLOG messages at or below this level.
	// Valid values: 0, 1, 2, 3, 4, 5
	// dynamic: true
	"--v": int & >=0 & <=5 | *0

	// Maximum time (in seconds) to buffer logs before writing to file.
	// 0 means real-time logging.
	"--logbufsecs": number & >=0 | *0

	// Whether to redirect stdout/stderr to separate log files.
	"--redirect_stdout": bool | *true

	// File name for standard output logs.
	"--stdout_log_file": string | *"graphd-stdout.log"

	// File name for standard error logs.
	"--stderr_log_file": string | *"graphd-stderr.log"

	// Minimum log level that will be copied to stderr.
	// Valid values: 0 (INFO), 1 (WARNING), 2 (ERROR), 3 (FATAL)
	"--stderrthreshold": int & >=0 & <=3 | *3

	// Whether to include timestamp in log file names.
	"--timestamp_in_logfile_name": bool | *true

	// Whether to treat partial success as error. Only applies to read-only requests.
    // Write requests always treat partial success as error.
    // When enabled, queries with partial success will return "Got partial result".
    "--accept_partial_success": bool | *false

    // Interval (in seconds) to send session information to Meta service.
    "--session_reclaim_interval_secs": int & >0 | *60

    // Maximum allowed query statement size in bytes.
    // Default is 4194304 (4MB).
    "--max_allowed_query_size": int & >0 | *4194304

    // Comma-separated list of all Meta service addresses (IP/hostname:port).
    // Example: "meta1:9559,meta2:9559"
    "--meta_server_addrs": string | *"127.0.0.1:9559"

    // Local IP address used to identify this graphd instance.
    // For distributed clusters or remote access, change it accordingly.
    "--local_ip": string | *"127.0.0.1"

    // Network device to bind to (e.g., 'any' means all interfaces).
    "--listen_netdev": string | *"any"

    // RPC port for the Graph service.
    "--port": int & >=1024 & <=65535 | *9669

    // Whether to enable SO_REUSEPORT socket option.
    "--reuse_port": bool | *false

    // Maximum length of the pending connection queue.
    // Should be adjusted along with net.core.somaxconn system setting.
    "--listen_backlog": int & >=1 & <=65535 | *1024

    // Timeout in seconds for idle client connections.
    // Range: 1 ~ 604800 seconds (default: 8 hours)
    "--client_idle_timeout_secs": int & >=1 & <=604800 | *28800

    // Timeout in seconds for idle sessions.
    // Range: 1 ~ 604800 seconds (default: 8 hours)
    "--session_idle_timeout_secs": int & >=1 & <=604800 | *28800

    // Number of threads to accept incoming connections.
    "--num_accept_threads": int & >=1 & <=100 | *1

    // Number of network I/O threads. 0 means use number of CPU cores.
    "--num_netio_threads": int & >=0 & <=100 | *0

    // Maximum number of active connections across all network threads.
    // 0 means no limit.
    // Per-thread limit = num_max_connections / num_netio_threads
    "--num_max_connections": int & >=0 | *0

    // Number of threads to execute user queries.
    // 0 means use number of CPU cores.
    "--num_worker_threads": int & >=0 & <=100 | *0

    // IP address for HTTP service (metrics, REST API).
    "--ws_ip": string | *"0.0.0.0"

    // Port for HTTP service (metrics, REST API).
    "--ws_http_port": int & >=1024 & <=65535 | *19669

    // Default heartbeat interval between services (in seconds).
    // Must be consistent across all services; otherwise, the system may malfunction.
    "--heartbeat_interval_secs": int & >0 | *10

    // Timeout in milliseconds for RPC connection to Storage service.
    // Default value is 60000 ms if not set.
    "--storage_client_timeout_ms": int & >=1000 & <=300000 | *60000

    // Threshold in microseconds for slow query logging.
    // Queries longer than this are considered slow.
    // DML statements are excluded from slow query logging.
    "--slow_query_threshold_us": int & >=1000 & <=10000000 | *200000

    // HTTP port for Meta service in integrated compute-storage version.
    // Must match `ws_http_port` in Meta service config.
    "--ws_meta_http_port": int & >=1024 & <=65535 | *19559

    // Whether to enable authorization when user logs in.
    // More details: https://docs.nebula-graph.io/manual/zh-CN/security/authentication/
    "--enable_authorize": bool | *false

    // Authentication type when user logs in.
    // Valid values: "password", "ldap", "cloud"
    "--auth_type": string & ("password" | "ldap" | "cloud") | *"password"

    // High watermark ratio for system memory usage.
    // When system memory usage exceeds this ratio (0.0 ~ 1.0),
    // NebulaGraph will stop accepting queries to prevent OOM.
    "--system_memory_high_watermark_ratio": number & >=0.0 & <=1.0 | *0.8

    // Whether to enable space-level metrics monitoring.
    // When enabled, metric names will include the graph space name,
    // e.g., query_latency_us{space=basketballplayer}.avg.3600.
    "--enable_space_level_metrics": bool | *false

    // Maximum number of sessions per user per IP address.
    "--max_sessions_per_ip_per_user": int & >=1 & <=10000 | *300

    // Whether to enable experimental features.
    // Valid values: true or false
    "--enable_experimental_feature": bool | *false

    // Whether to enable data balance (shard rebalance).
    // Only takes effect when enable_experimental_feature is true.
    "--enable_data_balance": bool | *true

    // Maximum job size (number of threads used for parallel execution phases).
    // Recommended value: half the number of physical CPU cores.
    "--max_job_size": int & >=1 & <=256 | *1

    // Minimum batch size for processing datasets.
    // Only takes effect when max_job_size > 1.
    "--min_batch_size": int & >=1024 & <=131072 | *8192

    // Whether to enable optimize_appendvertices behavior.
    // When enabled, MATCH statements will not filter dangling edges.
    "--optimize_appendvertices": bool | *false

    // Number of paths built per thread during path building phase.
    "--path_batch_size": int & >=1000 & <=100000 | *10000
}

configuration: #NebulaGraphdParameter & {

}
