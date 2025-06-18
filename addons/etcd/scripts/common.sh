#!/bin/bash

# config file used to bootstrap the etcd cluster
config_file="$TMP_CONFIG_PATH"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
  log "ERROR: $1" >&2
  exit 1
}

# Standard library loading function - can be sourced by all scripts
load_common_library() {
  kblib_common_library_file="/scripts/kb-common.sh"
  etcd_common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  . "${kblib_common_library_file}"
  # shellcheck disable=SC1090
  . "${etcd_common_library_file}"
}

# Standard shellspec magic - can be used by all scripts
setup_shellspec() {
  ${__SOURCED__:+false} : || return 0
}

# execute etcdctl command with proper TLS settings and auto protocol detection
exec_etcdctl() {
  local endpoint="$1"
  shift

  # Auto-detect protocol and add prefix if not present
  if [[ "$endpoint" != http://* ]] && [[ "$endpoint" != https://* ]]; then
    if get_protocol "advertise-client-urls" | grep -q "https"; then
      endpoint="https://$endpoint"
    else
      endpoint="http://$endpoint"
    fi
  fi

  if get_protocol "advertise-client-urls" | grep -q "https"; then
    [ ! -d "$TLS_MOUNT_PATH" ] && echo "ERROR: TLS_MOUNT_PATH '$TLS_MOUNT_PATH' not found" >&2 && return 1
    for cert in ca.pem cert.pem key.pem; do
      [ ! -s "$TLS_MOUNT_PATH/$cert" ] && echo "ERROR: TLS certificate '$cert' missing or empty" >&2 && return 1
    done
    etcdctl --endpoints="$endpoint" --cacert="$TLS_MOUNT_PATH/ca.pem" --cert="$TLS_MOUNT_PATH/cert.pem" --key="$TLS_MOUNT_PATH/key.pem" "$@"
  else
    etcdctl --endpoints="$endpoint" "$@"
  fi
}

# Unified protocol detection function - replaces get_client_protocol and get_peer_protocol
get_protocol() {
  local url_type="$1"

  if grep "$url_type" "$config_file" | grep -q 'https'; then
    echo "https"
  else
    echo "http"
  fi
}

# Convenience functions for backward compatibility
get_client_protocol() {
  get_protocol "advertise-client-urls"
}

get_peer_protocol() {
  get_protocol "initial-advertise-peer-urls"
}

check_backup_file() {
  local backup_file="$1"

  if [ ! -f "$backup_file" ]; then
    echo "ERROR: Backup file $backup_file does not exist" >&2
    return 1
  fi
  etcdutl snapshot status "$backup_file"
}

get_pod_endpoint_with_lb() {
  local lb_endpoints="$1"
  local pod_name="$2"
  local result_endpoint="$3"

  if [ -n "$lb_endpoints" ]; then
    log "LoadBalancer mode detected. Adapting pod FQDN to balance IP."
    local endpoints lb_endpoint
    endpoints=$(echo "$lb_endpoints" | tr ',' '\n')
    lb_endpoint=$(echo "$endpoints" | grep "$pod_name" | head -1)
    if [ -n "$lb_endpoint" ]; then
      # e.g.1 etcd-cluster-etcd-0
      # e.g.2 etcd-cluster-etcd-0:127.0.0.1
      if echo "$lb_endpoint" | grep -q ":"; then
        result_endpoint=$(echo "$lb_endpoint" | cut -d: -f2)
      else
        result_endpoint="$lb_endpoint"
      fi
      log "Using LoadBalancer endpoint for $pod_name: $result_endpoint"
    else
      log "Failed to get LB endpoint for $pod_name, using default FQDN: $result_endpoint"
    fi
  fi
  echo "$result_endpoint"
}

get_current_leader() {
  local contact_point="$1"
  local peer_endpoints leader_endpoint

  peer_endpoints=$(exec_etcdctl "$contact_point" member list | awk -F', ' '{if($5) print $5}' | paste -sd, -)
  if [ -z "$peer_endpoints" ]; then
    error_exit "No peer endpoints found"
  fi

  # Get status from all endpoints and find the leader
  local status_output leader_id endpoint
  status_output=$(exec_etcdctl "$peer_endpoints" endpoint status -w fields)

  leader_id=$(echo "$status_output" | grep -o '"Leader" : [0-9]*' | head -1 | awk '{print $3}')

  if [ -z "$leader_id" ]; then
    error_exit "Leader ID not found in endpoint status"
  fi

  # Find which endpoint has this leader ID as its member ID
  leader_endpoint=$(echo "$status_output" | awk -v leader_id="$leader_id" '
    BEGIN { current_endpoint = ""; current_member_id = "" }
    /"Endpoint" : / { 
      gsub(/"/, "", $3); 
      current_endpoint = $3 
    }
    /"MemberID" : / { 
      current_member_id = $3;
      if (current_member_id == leader_id && current_endpoint != "") {
        print current_endpoint;
        exit
      }
    }
  ')

  if [ -z "$leader_endpoint" ]; then
    error_exit "Leader not found among peers"
  fi

  echo "$leader_endpoint"
}

get_etcd_id() {
  local endpoint="$1"
  exec_etcdctl "$endpoint" endpoint status -w fields | grep -o '"MemberID" : [0-9]*' | awk '{print $3}'
}

get_member_and_leader_id() {
  local endpoint="$1"
  local status member_id leader_id

  status=$(exec_etcdctl "$endpoint" endpoint status -w fields)
  member_id=$(echo "$status" | grep -o '"MemberID" : [0-9]*' | awk '{print $3}')
  leader_id=$(echo "$status" | grep -o '"Leader" : [0-9]*' | awk '{print $3}')

  echo "$member_id $leader_id"
}

parse_config_value() {
  local key="$1"
  local config_file="$2"
  grep -E "^$key:" "$config_file" |
    sed -E \
      -e "s/^$key:[[:space:]]*//" \
      -e 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

get_etcd_role() {
  local status member_id leader_id is_learner
  if ! status=$(exec_etcdctl 127.0.0.1:2379 endpoint status -w fields --command-timeout=300ms --dial-timeout=100ms); then
    echo "ERROR: Failed to get endpoint status" >&2
    return 1
  fi

  member_id=$(echo "$status" | grep -o '"MemberID" : [0-9]*' | awk '{print $3}')
  leader_id=$(echo "$status" | grep -o '"Leader" : [0-9]*' | awk '{print $3}')
  is_learner=$(echo "$status" | grep -o '"IsLearner" : [a-z]*' | awk '{print $3}')

  if [ "$member_id" = "$leader_id" ]; then
    if [ "$is_learner" = "true" ]; then
      echo "learner"
    else
      echo "leader"
    fi
  else
    if [ "$is_learner" = "true" ]; then
      echo "learner"
    else
      echo "follower"
    fi
  fi
}
