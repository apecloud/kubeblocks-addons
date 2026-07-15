#!/usr/bin/env bash

set -uo pipefail

script=$1
family=$2
scenario=$3

# shellcheck source=/dev/null
source "$script"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
count_file="$tmp_dir/count"
fix_file="$tmp_dir/fix"
mutation_file="$tmp_dir/mutation"
printf '0\n' >"$count_file"
printf '0\n' >"$fix_file"
printf '0\n' >"$mutation_file"

ut_mode=true
network_mode=default
CURRENT_SHARD_COMPONENT_SHORT_NAME=shard-new
CURRENT_SHARD_COMPONENT_NAME=redis-shard-new
CURRENT_SHARD_POD_NAME_LIST=redis-shard-new-0,redis-shard-new-1
KB_CLUSTER_POD_NAME_LIST=redis-shard-a-0,redis-shard-a-1,redis-shard-b-0,redis-shard-b-1,redis-shard-c-0,redis-shard-c-1,redis-shard-new-0,redis-shard-new-1
KB_CLUSTER_POD_FQDN_LIST=$KB_CLUSTER_POD_NAME_LIST
KB_CLUSTER_COMPONENT_LIST=shard-a,shard-b,shard-c,shard-new
SERVICE_PORT=6379
REDIS_CLUSTER_RESHARD_BATCH_SIZE=128
[[ $scenario == invalid-batch ]] && REDIS_CLUSTER_RESHARD_BATCH_SIZE=0

is_empty() { [[ -z $1 ]]; }
sleep_when_ut_mode_false() { :; }

init_other_components_and_pods_info() {
  other_component_nodes=(10.42.0.10:6379)
  other_components=(shard-a shard-b shard-c)
  other_component_pod_names=(redis-shard-a-0)
}

init_current_comp_default_nodes_for_scale_out() {
  declare -gA scale_out_shard_default_primary_node
  declare -gA scale_out_shard_default_other_nodes
  scale_out_shard_default_primary_node=([redis-shard-new-0]=10.42.0.20:6379)
  scale_out_shard_default_other_nodes=()
}

get_cluster_id() { printf 'new-primary-id\n'; }
check_current_shard_other_nodes_are_joined() { return 0; }
check_node_in_cluster() { return 0; }
find_exist_available_node() { printf '10.42.0.10:6379\n'; }
scale_out_shard_primary_join_cluster() { return 0; }
secondary_replicated_to_primary() { return 0; }

inspect_redis_cluster_check() {
  case $scenario in
    views)
      redis_cluster_check_state=views-disagreement
      redis_cluster_check_output='[ERR] Nodes do not agree about configuration! All 16384 slots covered.'
      redis_cluster_check_rc=1
      ;;
    probe-error)
      redis_cluster_check_state=probe-error
      redis_cluster_check_output='Could not connect to Redis'
      redis_cluster_check_rc=1
      ;;
    open|repair-failure)
      redis_cluster_check_state=open-or-uncovered
      redis_cluster_check_output='[WARNING] The following slots are open: 12043. Not all 16384 slots are covered by nodes.'
      redis_cluster_check_rc=1
      ;;
    *)
      redis_cluster_check_state=stable
      redis_cluster_check_output='[OK] All 16384 slots covered.'
      redis_cluster_check_rc=0
      ;;
  esac
  return 0
}

fix_cluster_slots() {
  local count
  count=$(cat "$fix_file")
  printf '%s\n' "$((count + 1))" >"$fix_file"
  [[ $scenario == repair-failure ]] && return 1
  return 0
}

count_node_slots() {
  local count value
  count=$(cat "$count_file")
  printf '%s\n' "$((count + 1))" >"$count_file"
  case $scenario in
    large) [[ $count -eq 0 ]] && value=0 || value=128 ;;
    reentry) [[ $count -eq 0 ]] && value=128 || value=256 ;;
    final) [[ $count -eq 0 ]] && value=4000 || value=4096 ;;
    post-count-error)
      if [[ $count -eq 0 ]]; then
        value=0
      else
        printf 'count failed\n' >&2
        return 1
      fi
      ;;
    *) value=0 ;;
  esac
  printf '%s\n' "$value"
}

scale_out_shard_reshard() {
  local count
  count=$(cat "$mutation_file")
  printf '%s\n' "$((count + 1))" >"$mutation_file"
  printf 'reshard_slots=%s\n' "$3"
  [[ $scenario == mutation-failure ]] && return 1
  return 0
}

set +e
output=$(scale_out_redis_cluster_shard 2>&1)
status=$?
set -e

printf 'family=%s scenario=%s status=%s mutation=%s fix=%s\n' \
  "$family" "$scenario" "$status" "$(cat "$mutation_file")" "$(cat "$fix_file")"
printf '%s\n' "$output"
