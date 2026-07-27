#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

require_env() {
  local name=$1
  if [ -z "${!name:-}" ]; then
    printf 'missing %s\n' "$name" >&2
    return 1
  fi
}

managed_shardadd_inputs=false
prepare_managed_shardadd_inputs() {
  if [ -n "${REDIS_CLUSTER_ENDPOINT:-}" ] &&
     [ -n "${REDIS_TARGET_SHARD_COUNT:-}" ] &&
     [ -n "${REDIS_NEW_MASTER_IDS:-}" ]; then
    return 0
  fi
  if [ -z "${KB_SHARD_ADD_TOKEN:-}${KB_SHARDING_NAME:-}${KB_SHARD_ADD_SHARDS:-}${KB_SHARD_COUNT:-}" ]; then
    return 0
  fi

  require_env KB_SHARD_ADD_TOKEN
  require_env KB_SHARDING_NAME
  require_env KB_SHARD_ADD_SHARDS
  require_env KB_SHARD_COUNT
  require_env REDIS_SOURCE_POD_NAME
  require_env REDIS_SOURCE_COMPONENT_NAME
  require_env REDIS_CLUSTER_NAMESPACE
  require_env REDIS_CLUSTER_DOMAIN
  require_env REDIS_SERVICE_PORT

  if [[ "$KB_SHARD_ADD_SHARDS" == ,* ]] ||
     [[ "$KB_SHARD_ADD_SHARDS" == *, ]] ||
     [[ "$KB_SHARD_ADD_SHARDS" == *,,* ]]; then
    printf 'KB_SHARD_ADD_SHARDS contains an empty component name\n' >&2
    return 1
  fi

  local component
  local normalized_components
  normalized_components=$(printf '%s\n' "$KB_SHARD_ADD_SHARDS" | tr ',' '\n')
  while IFS= read -r component; do
    if ! [[ "$component" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]]; then
      printf 'KB_SHARD_ADD_SHARDS contains an invalid component name\n' >&2
      return 1
    fi
  done <<<"$normalized_components"
  if [ "$(printf '%s\n' "$normalized_components" | LC_ALL=C sort | uniq -d | wc -l | tr -d ' ')" != "0" ]; then
    printf 'KB_SHARD_ADD_SHARDS contains duplicate component names\n' >&2
    return 1
  fi
  if ! [[ "$REDIS_SERVICE_PORT" =~ ^[1-9][0-9]*$ ]] || [ "$REDIS_SERVICE_PORT" -gt 65535 ]; then
    printf 'REDIS_SERVICE_PORT must be a valid TCP port\n' >&2
    return 1
  fi

  REDIS_CLUSTER_ENDPOINT="${REDIS_SOURCE_POD_NAME}.${REDIS_SOURCE_COMPONENT_NAME}-headless.${REDIS_CLUSTER_NAMESPACE}.svc.${REDIS_CLUSTER_DOMAIN}:${REDIS_SERVICE_PORT}"
  REDIS_TARGET_SHARD_COUNT=$KB_SHARD_COUNT
  managed_shardadd_inputs=true
}

prepare_managed_shardadd_inputs

require_env REDIS_CLUSTER_ENDPOINT
require_env REDIS_TARGET_SHARD_COUNT

if ! [[ "$REDIS_TARGET_SHARD_COUNT" =~ ^[1-9][0-9]*$ ]]; then
  printf 'REDIS_TARGET_SHARD_COUNT must be a positive integer\n' >&2
  exit 1
fi

validate_new_master_ids() {
  local master_id
  local normalized_ids

  normalized_ids=$(printf '%s\n' "$REDIS_NEW_MASTER_IDS" | tr ',' '\n')
  while IFS= read -r master_id; do
    if ! [[ "$master_id" =~ ^[[:xdigit:]]{40}$ ]]; then
      printf 'REDIS_NEW_MASTER_IDS contains an invalid Redis node ID\n' >&2
      return 1
    fi
  done <<<"$normalized_ids"

  if [ "$(printf '%s\n' "$normalized_ids" | LC_ALL=C sort | uniq -d | wc -l | tr -d ' ')" != "0" ]; then
    printf 'REDIS_NEW_MASTER_IDS contains duplicate Redis node IDs\n' >&2
    return 1
  fi
}

if [ "$managed_shardadd_inputs" = false ]; then
  require_env REDIS_NEW_MASTER_IDS
  validate_new_master_ids
fi

REDIS_COMMAND_TIMEOUT_SECONDS=${REDIS_COMMAND_TIMEOUT_SECONDS:-300}
REDIS_COMMAND_KILL_GRACE_SECONDS=${REDIS_COMMAND_KILL_GRACE_SECONDS:-10}
for timeout_value in "$REDIS_COMMAND_TIMEOUT_SECONDS" "$REDIS_COMMAND_KILL_GRACE_SECONDS"; do
  if ! [[ "$timeout_value" =~ ^[1-9][0-9]*$ ]]; then
    printf 'Redis command timeout values must be positive integers\n' >&2
    exit 1
  fi
done

if ! command -v timeout >/dev/null 2>&1; then
  printf 'timeout command is required for bounded Redis operations\n' >&2
  exit 1
fi

parse_endpoint() {
  local endpoint=$1
  if [[ "$endpoint" =~ ^\[([^]]+)\]:([0-9]+)$ ]]; then
    PARSED_HOST=${BASH_REMATCH[1]}
    PARSED_PORT=${BASH_REMATCH[2]}
  elif [[ "$endpoint" =~ ^([^:]+):([0-9]+)$ ]]; then
    PARSED_HOST=${BASH_REMATCH[1]}
    PARSED_PORT=${BASH_REMATCH[2]}
  else
    printf 'invalid Redis endpoint: %s\n' "$endpoint" >&2
    return 1
  fi
}

if redis_cli_version=$(timeout \
  -s TERM -k "${REDIS_COMMAND_KILL_GRACE_SECONDS}s" \
  "${REDIS_COMMAND_TIMEOUT_SECONDS}s" redis-cli --version); then
  :
else
  version_rc=$?
  if [ "$version_rc" -eq 124 ] || [ "$version_rc" -eq 137 ]; then
    printf 'redis-cli version probe timed out after %s seconds\n' "$REDIS_COMMAND_TIMEOUT_SECONDS" >&2
  else
    printf 'unable to execute redis-cli version probe\n' >&2
  fi
  exit "$version_rc"
fi
if ! [[ "$redis_cli_version" =~ redis-cli[[:space:]]+([0-9]+)\. ]]; then
  printf 'unable to determine redis-cli major version\n' >&2
  exit 1
fi
redis_cli_major=${BASH_REMATCH[1]}
case "$redis_cli_major" in
  5|6|7|8) ;;
  *)
    printf 'unsupported redis-cli major version: %s\n' "$redis_cli_major" >&2
    exit 1
    ;;
esac

declare -a redis_cli_common_args=()
if [ "$redis_cli_major" -ge 6 ] && [ -n "${REDIS_DEFAULT_USER:-}" ] && [ "$REDIS_DEFAULT_USER" != "default" ]; then
  redis_cli_common_args+=(--user "$REDIS_DEFAULT_USER")
fi

case "${REDIS_TLS_ENABLED:-false}" in
  false|FALSE|0|"") ;;
  true|TRUE|1)
    require_env REDIS_TLS_CA_FILE
    require_env REDIS_TLS_CERT_FILE
    require_env REDIS_TLS_KEY_FILE
    for tls_file in "$REDIS_TLS_CA_FILE" "$REDIS_TLS_CERT_FILE" "$REDIS_TLS_KEY_FILE"; do
      if [ ! -r "$tls_file" ]; then
        printf 'Redis TLS file is not readable: %s\n' "$tls_file" >&2
        exit 1
      fi
    done
    redis_cli_common_args+=(
      --tls
      --cacert "$REDIS_TLS_CA_FILE"
      --cert "$REDIS_TLS_CERT_FILE"
      --key "$REDIS_TLS_KEY_FILE"
    )
    ;;
  *)
    printf 'REDIS_TLS_ENABLED must be true or false\n' >&2
    exit 1
    ;;
esac

run_redis_cli() {
  local command_rc
  local -a command_args=(
    timeout
    -s TERM
    -k "${REDIS_COMMAND_KILL_GRACE_SECONDS}s"
    "${REDIS_COMMAND_TIMEOUT_SECONDS}s"
    redis-cli
  )

  if [ "${#redis_cli_common_args[@]}" -gt 0 ]; then
    command_args+=("${redis_cli_common_args[@]}")
  fi
  command_args+=("$@")

  if [ -n "${REDIS_DEFAULT_PASSWORD:-}" ]; then
    if REDISCLI_AUTH="$REDIS_DEFAULT_PASSWORD" "${command_args[@]}"; then
      return 0
    else
      command_rc=$?
    fi
  elif "${command_args[@]}"; then
    return 0
  else
    command_rc=$?
  fi

  if [ "$command_rc" -eq 124 ] || [ "$command_rc" -eq 137 ]; then
    printf 'redis-cli command timed out after %s seconds\n' "$REDIS_COMMAND_TIMEOUT_SECONDS" >&2
  fi
  return "$command_rc"
}

cluster_nodes_for_endpoint() {
  local endpoint=$1
  parse_endpoint "$endpoint"
  run_redis_cli -h "$PARSED_HOST" -p "$PARSED_PORT" cluster nodes
}

cluster_info_for_endpoint() {
  local endpoint=$1
  parse_endpoint "$endpoint"
  run_redis_cli -h "$PARSED_HOST" -p "$PARSED_PORT" cluster info
}

healthy_master_ids_for_component() {
  local nodes=$1
  local component=$2
  local service_fqdn
  local ids

  ids=$(printf '%s\n' "$nodes" | awk -v component="$component" '
    function node_host(raw, parts, base, announced) {
      split(raw, parts, ",")
      announced = parts[2]
      if (announced != "") {
        return announced
      }
      base = parts[1]
      sub(/@.*/, "", base)
      sub(/:[0-9]+$/, "", base)
      return base
    }
    NF >= 8 && $3 ~ /master/ && $3 !~ /(fail|handshake|noaddr)/ {
      host = node_host($2)
      if (index(host, "." component "-headless.") > 0) {
        print $1
      }
    }
  ' | LC_ALL=C sort -u)
  if [ -n "$ids" ]; then
    printf '%s\n' "$ids"
    return 0
  fi

  command -v getent >/dev/null 2>&1 || return 0
  service_fqdn="${component}-headless.${REDIS_CLUSTER_NAMESPACE}.svc.${REDIS_CLUSTER_DOMAIN}"
  local service_ips
  service_ips=$(getent ahostsv4 "$service_fqdn" 2>/dev/null | awk '{print $1}' | LC_ALL=C sort -u)
  [ -n "$service_ips" ] || return 0
  printf '%s\n' "$nodes" | awk -v service_ips="$service_ips" '
    BEGIN {
      count = split(service_ips, entries, "\n")
      for (i = 1; i <= count; i++) {
        ips[entries[i]] = 1
      }
    }
    NF >= 8 && $3 ~ /master/ && $3 !~ /(fail|handshake|noaddr)/ {
      split($2, address_parts, ",")
      address = address_parts[1]
      sub(/@.*/, "", address)
      sub(/:[0-9]+$/, "", address)
      if (ips[address]) {
        print $1
      }
    }
  ' | LC_ALL=C sort -u
}

derive_new_master_ids() {
  local nodes
  local component
  local component_ids
  local component_id
  local derived_ids=""

  nodes=$(cluster_nodes_for_endpoint "$REDIS_CLUSTER_ENDPOINT")
  while IFS= read -r component; do
    [ -n "$component" ] || continue
    component_ids=$(healthy_master_ids_for_component "$nodes" "$component")
    if [ "$(printf '%s\n' "$component_ids" | sed '/^$/d' | wc -l | tr -d ' ')" != "1" ]; then
      printf 'KB_SHARD_ADD_SHARDS component %s does not map to exactly one healthy Redis master\n' "$component" >&2
      return 1
    fi
    component_id=$(printf '%s\n' "$component_ids" | sed -n '1p')
    derived_ids="${derived_ids}${derived_ids:+,}${component_id}"
  done < <(printf '%s\n' "$KB_SHARD_ADD_SHARDS" | tr ',' '\n')
  REDIS_NEW_MASTER_IDS=$derived_ids
}

if [ "$managed_shardadd_inputs" = true ]; then
  derive_new_master_ids
  validate_new_master_ids
fi

normalize_cluster_nodes() {
  awk '
    function canonical_address(raw, parts, base, announced, port) {
      split(raw, parts, ",")
      base = parts[1]
      sub(/@.*/, "", base)
      port = base
      sub(/^.*:/, "", port)
      announced = parts[2]
      if (announced != "") {
        return announced ":" port
      }
      return base
    }
    NF >= 8 {
      address = canonical_address($2)
      flags = ""
      flag_count = split($3, flag_parts, ",")
      for (flag = 1; flag <= flag_count; flag++) {
        if (flag_parts[flag] != "myself") {
          flags = flags (flags == "" ? "" : ",") flag_parts[flag]
        }
      }
      slots = ""
      for (field = 9; field <= NF; field++) {
        slots = slots (slots == "" ? "" : " ") $field
      }
      print $1 "|" address "|" flags "|" $4 "|" $7 "|" $8 "|" slots
    }
  ' | LC_ALL=C sort
}

cluster_endpoints_from_nodes() {
  awk '
    function canonical_address(raw, parts, base, announced, port) {
      split(raw, parts, ",")
      base = parts[1]
      sub(/@.*/, "", base)
      port = base
      sub(/^.*:/, "", port)
      announced = parts[2]
      if (announced != "") {
        return announced ":" port
      }
      return base
    }
    NF >= 8 && $3 !~ /(fail|handshake|noaddr)/ {
      print canonical_address($2)
    }
  ' | LC_ALL=C sort -u
}

assert_node_views_agree() {
  local seed_nodes=$1
  local expected_view
  local endpoint
  local actual_view

  expected_view=$(printf '%s\n' "$seed_nodes" | normalize_cluster_nodes)
  while IFS= read -r endpoint; do
    [ -n "$endpoint" ] || continue
    actual_view=$(cluster_nodes_for_endpoint "$endpoint" | normalize_cluster_nodes)
    if [ "$actual_view" != "$expected_view" ]; then
      printf 'Redis Cluster node views do not agree: %s differs from %s\n' \
        "$endpoint" "$REDIS_CLUSTER_ENDPOINT" >&2
      return 1
    fi
  done < <(printf '%s\n' "$seed_nodes" | cluster_endpoints_from_nodes)
}

cluster_check_output() {
  run_redis_cli --cluster check "$REDIS_CLUSTER_ENDPOINT"
}

cluster_check_is_stable() {
  local output=$1
  printf '%s\n' "$output" | grep -q 'All 16384 slots covered' || return 1
  if printf '%s\n' "$output" | grep -Eq '\[ERR\]|slots are open|importing state|migrating state'; then
    return 1
  fi
}

cluster_info_value() {
  local info=$1
  local key=$2
  printf '%s\n' "$info" | awk -F: -v key="$key" '$1 == key { gsub(/\r/, "", $2); print $2; exit }'
}

new_masters_own_slots() {
  local nodes=$1
  local master_id
  local node_line

  while IFS= read -r master_id; do
    [ -n "$master_id" ] || continue
    node_line=$(printf '%s\n' "$nodes" | awk -v id="$master_id" '$1 == id { print; exit }')
    [ -n "$node_line" ] || return 1
    printf '%s\n' "$node_line" | awk 'NF >= 9 && $3 ~ /master/ && $3 !~ /(fail|handshake|noaddr)/ { found = 1 } END { exit(found ? 0 : 1) }' || return 1
  done < <(printf '%s\n' "$REDIS_NEW_MASTER_IDS" | tr ',' '\n')
}

new_masters_are_healthy_masters() {
  local nodes=$1
  local master_id
  local matches

  while IFS= read -r master_id; do
    [ -n "$master_id" ] || continue
    matches=$(printf '%s\n' "$nodes" | awk -v id="$master_id" '$1 == id { count++ } END { print count + 0 }')
    [ "$matches" = "1" ] || return 1
    printf '%s\n' "$nodes" | awk -v id="$master_id" '
      $1 == id && $3 ~ /master/ && $3 !~ /(fail|handshake|noaddr)/ { healthy = 1 }
      END { exit(healthy ? 0 : 1) }
    ' || return 1
  done < <(printf '%s\n' "$REDIS_NEW_MASTER_IDS" | tr ',' '\n')
}

topology_is_converged() {
  local nodes=$1
  local info=$2
  local check=$3
  local master_count

  [ "$(cluster_info_value "$info" cluster_state)" = "ok" ] || return 1
  [ "$(cluster_info_value "$info" cluster_slots_assigned)" = "16384" ] || return 1
  [ "$(cluster_info_value "$info" cluster_slots_ok)" = "16384" ] || return 1
  [ "$(cluster_info_value "$info" cluster_slots_pfail)" = "0" ] || return 1
  [ "$(cluster_info_value "$info" cluster_slots_fail)" = "0" ] || return 1
  [ "$(cluster_info_value "$info" cluster_size)" = "$REDIS_TARGET_SHARD_COUNT" ] || return 1
  cluster_check_is_stable "$check" || return 1

  master_count=$(printf '%s\n' "$nodes" | awk '$3 ~ /master/ && $3 !~ /(fail|handshake|noaddr)/ { count++ } END { print count + 0 }')
  [ "$master_count" = "$REDIS_TARGET_SHARD_COUNT" ] || return 1
  new_masters_own_slots "$nodes"
}

seed_nodes=$(cluster_nodes_for_endpoint "$REDIS_CLUSTER_ENDPOINT")
assert_node_views_agree "$seed_nodes"
if ! new_masters_are_healthy_masters "$seed_nodes"; then
  printf 'Supplied new Redis master IDs are not unique healthy masters\n' >&2
  exit 1
fi
seed_info=$(cluster_info_for_endpoint "$REDIS_CLUSTER_ENDPOINT")
seed_check=$(cluster_check_output)

if topology_is_converged "$seed_nodes" "$seed_info" "$seed_check"; then
  printf 'Redis Cluster shardAdd topology already converged\n'
  exit 0
fi

if printf '%s\n' "$seed_check" | grep -Eq 'slots are open|importing state|migrating state'; then
  run_redis_cli --cluster fix "$REDIS_CLUSTER_ENDPOINT" --cluster-yes
  seed_nodes=$(cluster_nodes_for_endpoint "$REDIS_CLUSTER_ENDPOINT")
  assert_node_views_agree "$seed_nodes"
elif printf '%s\n' "$seed_check" | grep -q '\[ERR\]'; then
  printf 'Redis Cluster check reported an unrecoverable error before rebalance\n' >&2
  exit 1
fi

run_redis_cli --cluster rebalance "$REDIS_CLUSTER_ENDPOINT" \
  --cluster-use-empty-masters --cluster-yes

final_nodes=$(cluster_nodes_for_endpoint "$REDIS_CLUSTER_ENDPOINT")
assert_node_views_agree "$final_nodes"
final_info=$(cluster_info_for_endpoint "$REDIS_CLUSTER_ENDPOINT")
final_check=$(cluster_check_output)

if ! topology_is_converged "$final_nodes" "$final_info" "$final_check"; then
  printf 'Redis Cluster shardAdd rebalance finished without topology convergence\n' >&2
  exit 1
fi

printf 'Redis Cluster shardAdd rebalance completed and topology converged\n'
