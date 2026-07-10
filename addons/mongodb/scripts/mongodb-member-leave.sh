#!/bin/bash
set -euo pipefail

member_name="${KB_LEAVE_MEMBER_POD_NAME:-}"
if [ -z "$member_name" ]; then
  echo "KB_LEAVE_MEMBER_POD_NAME is required" >&2
  exit 1
fi

syncerctl_bin="${SYNCERCTL_BIN:-/tools/syncerctl}"
main_port="${SYNCER_MAIN_SERVICE_PORT:-3601}"
pbm_agent_port="${PBM_AGENT_SYNCER_SERVICE_PORT:-3361}"
call_timeout="${SYNCER_MEMBER_LEAVE_CALL_TIMEOUT:-60s}"

call_leave() {
  local port="$1"
  local target="$2"
  echo "calling ${target} memberLeave for ${member_name} on 127.0.0.1:${port}"
  timeout "$call_timeout" "$syncerctl_bin" --host 127.0.0.1 --port "$port" leave --instance "$member_name"
}

call_leave "$main_port" "mongodb"
call_leave "$pbm_agent_port" "pbm-agent"
