#!/bin/bash
set -ex

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  set -ex;
}

load_common_library() {
  kblib_common_library_file="/scripts/kb-common.sh"
  etcd_common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  . "${kblib_common_library_file}"
  # shellcheck disable=SC1090
  . "${etcd_common_library_file}"
}

get_current_leader() {
  local contact_point="$1"
  local peer_endpoints leader_endpoint

  peer_endpoints=$(exec_etcdctl "$contact_point" member list | awk -F', ' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $5); if($5) print $5}' | tr '\n' ',' | sed 's/,$//') || error_exit "Failed to get member list"
  [ -z "$peer_endpoints" ] && error_exit "No peer endpoints found"

  leader_endpoint=$(exec_etcdctl "$peer_endpoints" endpoint status -w fields --command-timeout=300ms --dial-timeout=100ms | while IFS=, read -r line; do
    echo "$line" | grep -q 'is_leader:"true"' && echo "$line" | grep -o 'endpoint:"[^"]*"' | cut -d'"' -f2 && exit 0
  done)
  [ -z "$leader_endpoint" ] && error_exit "Leader not found among peers"

  echo "$leader_endpoint"
}

get_current_leader_with_retry() {
  local origin="$1"
  local retry_count="$2"
  local retry_interval="$3"
  local leader

  leader=$(call_func_with_retry get_current_leader "$origin" "$retry_count" "$retry_interval")
  if [ -z "$leader" ]; then
    error_exit "Failed to get current leader after $retry_count retries"
  fi
  echo "$leader"
}

switchover_with_candidate() {
  local leader_endpoint candidate_endpoint current_leader candidate_id candidate_status is_leader

  leader_endpoint="$LEADER_POD_FQDN:2379"
  candidate_endpoint="$KB_SWITCHOVER_CANDIDATE_FQDN:2379"

  current_leader=$(get_current_leader_with_retry "$leader_endpoint" 3 2)
  if [ "$current_leader" = "$candidate_endpoint" ]; then
    echo "current leader is the same as candidate, no need to switch"
    return 0
  fi

  candidate_id=$(exec_etcdctl "$candidate_endpoint" endpoint status | awk -F', ' '{print $2}')
  exec_etcdctl "$leader_endpoint" move-leader "$candidate_id"

  candidate_status=$(exec_etcdctl "$candidate_endpoint" endpoint status)
  is_leader=$(echo "${candidate_status}" | awk -F ', ' '{print $5}')

  if [ "$is_leader" = "true" ]; then
    return 0
  elif [ "$is_leader" = "false" ]; then
    echo "candidate status is not leader after switchover, please check!" >&2
    return 1
  fi
  echo "candidate status '$candidate_status' is unexpected after switchover, please check!" >&2
  return 1
}

switchover_without_candidate() {
  local leader_endpoint current_leader leader_id peers_id candidate_id leader_status is_leader

  leader_endpoint="$LEADER_POD_FQDN:2379"

  current_leader=$(get_current_leader_with_retry "$leader_endpoint" 3 2)

  if [ "$leader_endpoint" != "$current_leader" ]; then
    echo "leader has been changed, do not perform switchover, please check!"
    return 0
  fi

  leader_id=$(exec_etcdctl "$leader_endpoint" endpoint status | awk -F', ' '{print $2}')
  peers_id=$(exec_etcdctl "$leader_endpoint" member list | awk -F', ' '{print $1}')
  candidate_id=$(echo "$peers_id" | grep -v "$leader_id" | awk 'NR==1')

  if is_empty "$candidate_id"; then
    echo "no candidate found" >&2
    return 1
  fi

  exec_etcdctl "$leader_endpoint" move-leader "$candidate_id"

  leader_status=$(exec_etcdctl "$leader_endpoint" endpoint status)
  is_leader=$(echo "$leader_status" | awk -F ', ' '{print $5}')
  
  if [ "$is_leader" = "false" ]; then
    return 0
  elif [ "$is_leader" = "true" ]; then
    echo "leader status is no changed after switchover, please check!" >&2
    return 1
  fi
  echo "leader status '$leader_status' is unexpected after switchover, please check!" >&2
  return 1
}

switchover() {
  local status

  if [[ $LEADER_POD_FQDN != "$KB_SWITCHOVER_CURRENT_FQDN" ]]; then
    echo "switchover action not triggered for leader pod. Exiting."
    exit 0
  fi

  if is_empty "$KB_SWITCHOVER_CANDIDATE_FQDN"; then
      switchover_without_candidate
  else
      switchover_with_candidate
  fi
  status=$?
  if [ "$status" -ne 0 ]; then
      echo "ERROR: Failed to switchover. Exiting." >&2
      return 1
  fi
  echo "Switchover successfully."
  return 0
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
switchover
