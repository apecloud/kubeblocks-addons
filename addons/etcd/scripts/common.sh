#!/bin/bash

# shellcheck disable=SC2039

# config file used to bootstrap the etcd cluster
config_file=$TMP_CONFIG_PATH

check_requirements() {
  if [[ $(uname) == "Darwin" || $(uname) == *"BSD"* ]] && ! which gsed > /dev/null 2>&1; then
    echo "cannot find gsed (required on BSD/Darwin systems)" >&2
    return 1
  fi
  return 0
}

universal_sed() {
  if [[ $(uname) == "Darwin" || $(uname) == *"BSD"* ]]; then
    gsed "$@"
  else
    sed "$@"
  fi
}

check_backup_file() {
  local backup_file=$1
  output=$(etcdutl snapshot status "${backup_file}")
  status=$?
  if [ $status -ne 0 ]; then
    echo "ERROR: Failed to check the backup file with etcdctl" >&2
    return 1
  fi
  total_key=$(echo "$output" | awk -F', ' '{print $3}')
  # check if total key is a number
  if [ -z "$total_key" ] || ! [[ "$total_key" =~ ^[0-9]+$ ]]; then
    echo "ERROR: snapshot totalKey is not a valid number." >&2
    return 1
  fi

  threshold=$BACKUP_KEY_THRESHOLD
  if [ "$total_key" -lt "$threshold" ]; then
    echo "WARNING: snapshot totalKey is less than the threshold" >&2
    return 1
  fi
  return 0
}

get_client_protocol() {
  # check client tls if is enabled
  line=$(grep 'advertise-client-urls' "${config_file}")
  if echo "$line" | grep -q 'https'; then
    echo "https"
  elif echo "$line" | grep -q 'http'; then
    echo "http"
  fi
}

get_peer_protocol() {
  # check peer tls if is enabled
  line=$(grep 'initial-advertise-peer-urls' "${config_file}")
  if echo "$line" | grep -q 'https'; then
    echo "https"
  elif echo "$line" | grep -q 'http'; then
    echo "http"
  fi
}

exec_etcdctl() {
  local endpoints=$1
  shift
  client_protocol=$(get_client_protocol)
  tls_dir=$TLS_MOUNT_PATH
  # check if the client_protocol is https and the tls_dir is not empty
  if [ "$client_protocol" = "https" ] && [ -d "$tls_dir" ] && [ -s "${tls_dir}/ca.crt" ] && [ -s "${tls_dir}/tls.crt" ] && [ -s "${tls_dir}/tls.key" ]; then
    etcdctl --endpoints="${endpoints}" --cacert="${tls_dir}/ca.crt" --cert="${tls_dir}/tls.crt" --key="${tls_dir}/tls.key" "$@"
  elif [ "$client_protocol" = "http" ]; then
    etcdctl --endpoints="${endpoints}" "$@"
  else
    echo "ERROR: bad etcdctl args: clientProtocol:${client_protocol}, endpoints:${endpoints}, tlsDir:${tls_dir}, please check!" >&2
    return 1
  fi
  status=$?
  if [ $status -ne 0 ]; then
    echo "etcdctl command failed" >&2
    return 1
  fi
  return 0
}

get_current_leader() {
  local leader_endpoint=$1
  peer_endpoints=$(exec_etcdctl "$leader_endpoint" member list | awk -F', ' '{print $5}' | tr '\n' ',' | universal_sed 's#,$##')
  leader_endpoint=$(exec_etcdctl "$peer_endpoints" endpoint status | awk -F', ' '$5=="true" {print $1}')
  if [ -z "$leader_endpoint" ]; then
    echo "leader is not ready" >&2
    return 1
  fi
  echo "${leader_endpoint}"
  return 0
}

get_current_leader_with_retry() {
  local origin_leader=$1
  local max_retries=$2
  local retry_delay=$3
  local current_leader
  current_leader=$(call_func_with_retry "$max_retries" "$retry_delay" get_current_leader "$origin_leader")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get current leader" >&2
    return 1
  fi
  echo "${current_leader}"
  return 0
}
