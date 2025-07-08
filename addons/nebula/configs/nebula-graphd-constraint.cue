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
    // This setting is not dynamically modifiable at runtime.
    --daemonize: bool | *true

    // File path to store the process ID (PID).
    // This setting is not dynamically modifiable at runtime.
    --pid_file: string | *"pids/nebula-metad.pid"

    // Time zone name, e.g., UTC+08:00 for China Standard Time.
    // Format reference: https://www.gnu.org/software/libc/manual/html_node/TZ-Variable.html
    // Default value: UTC+00:00 if not specified.
    // This setting is not dynamically modifiable at runtime.
    --timezone_name?: string | *"UTC+00:00:00"

    // Directory to store Meta service logs.
    // It is recommended to place logs and data on different disks.
    --log_dir: string

    // Minimum log level to record (INFO=0, WARNING=1, ERROR=2, FATAL=3).
    // Setting to 4 disables all logs.
    // Suggested values:
    //   - 0 (INFO) for debugging
    //   - 1 (WARNING) for production
    // dynamic: true
    --minloglevel: int & >=0 & <=4 & *0

    // VLOG verbosity level. Records VLOG messages at or below this level.
    // Valid values: 0, 1, 2, 3, 4, 5
    // dynamic: true
    --v: int & >=0 & <=5 & *0

    // Maximum time (in seconds) to buffer logs before writing to file.
    // 0 means real-time logging.
    --logbufsecs: int & >=0 & *0

    // Whether to redirect stdout/stderr to separate log files.
    --redirect_stdout: bool | *true

    // File name for standard output logs.
    --stdout_log_file: string | *"graphd-stdout.log"

    // File name for standard error logs.
    stderr_log_file: string & *"metad-stderr.log"

    // Minimum log level that will be copied to stderr.
    // Valid values: 0 (INFO), 1 (WARNING), 2 (ERROR), 3 (FATAL)
    stderrthreshold: int & >=0 & <=3 & *3

    // Whether to include timestamp in log file names.
    timestamp_in_logfile_name: bool & *true
}

configuration: #NebulaGraphdParameter & {

}
