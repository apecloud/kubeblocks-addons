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

#NebulaMetadParameter: {
    // Whether to run as a daemon process.
    // This setting is not dynamically modifiable at runtime.
    "--daemonize": bool | *true

    // File path to store the process ID (PID).
    // This setting is not dynamically modifiable at runtime.
    "--pid_file": string | *"pids/nebula-metad.pid"

    // Time zone name, e.g., UTC+08:00 for China Standard Time.
    // Format reference: https://www.gnu.org/software/libc/manual/html_node/TZ-Variable.html
    // Default value: UTC+00:00 if not specified.
    // This setting is not dynamically modifiable at runtime.
    "--timezone_name": string | *"UTC+00:00:00"

    // Directory to store Meta service logs.
    // It is recommended to place logs and data on different disks.
    "--log_dir": string

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
    "--logbufsecs": int & >=0 | *0

    // Whether to redirect stdout/stderr to separate log files.
    "--redirect_stdout": bool | *true

    // File name for standard output logs.
    "--stdout_log_file": string | *"metad-stdout.log"

    // File name for standard error logs.
    "--stderr_log_file": string | *"metad-stderr.log"

    // Minimum log level that will be copied to stderr.
    // Valid values: 0 (INFO), 1 (WARNING), 2 (ERROR), 3 (FATAL)
    "--stderrthreshold": int & >=0 & <=3 | *3

    // Whether to include timestamp in log file names.
    "--timestamp_in_logfile_name": bool | *true

    // Comma-separated list of all Meta service addresses (IP/hostname:port).
    // Example: "192.168.0.1:9559,192.168.0.2:9559"
    "--meta_server_addrs": string | *"127.0.0.1:9559"

    // Local IP address used to identify this metad instance.
    // For distributed clusters or remote access, change it accordingly.
    "--local_ip": string | *"127.0.0.1"

    // RPC port for the Meta service.
    // The next port (+1) is used for Raft communication between Meta services.
    "--port": int & >=1024 & <=65535 | *9559

    // IP address for HTTP service (e.g., metrics, REST API).
    "--ws_ip": string | *"0.0.0.0"

    // Port for HTTP service (metrics, REST API).
    "--ws_http_port": int & >=1024 & <=65535 | *19559

    // Port for Storage HTTP service in integrated compute-storage version.
    // Must match `ws_http_port` in Storage service config.
    "--ws_storage_http_port": int & >=1024 | <=65535

    // Directory path to store meta data.
    // This setting is not dynamically modifiable at runtime.
    "--data_path": string | *"data/meta"

    // Default number of partitions when creating a graph space.
	// This setting is not dynamically modifiable at runtime.
	"--default_parts_num": int & >0 | *10

	// Default number of replicas when creating a graph space.
	// This setting is not dynamically modifiable at runtime.
	"--default_replica_factor": int & >=1 | *1

	// Heartbeat interval between services (in seconds).
	// Must be consistent across all services; otherwise, the system may malfunction.
	"--heartbeat_interval_secs": int & >0 | *10

	// Heartbeat interval for Agent service (in seconds).
	// Affects how quickly the system detects Agent offline status.
	"--agent_heartbeat_interval_secs": int & >0 | *60

	// Whether to synchronize the RocksDB WAL (Write Ahead Log) to disk.
    // Enabling this improves data durability but may impact performance.
    "--rocksdb_wal_sync": bool | *true
}

configuration: #NebulaMetadParameter & {

}
