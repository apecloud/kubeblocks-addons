#!/usr/bin/env bash

set -euo pipefail

script=$1
family=$2
mode=${3:-classify}
scenario=${4:-target-first}

contains() {
  [[ $1 == *"$2"* ]]
}

is_empty() {
  [[ -z $1 ]]
}

getent() {
  case $2 in
    redis-shard-sxj-0.*) printf '10.42.0.227 %s\n' "$2" ;;
    redis-shard-sxj-1.*) printf '10.42.0.228 %s\n' "$2" ;;
    redis-shard-sxj-2.*) printf '10.42.0.230 %s\n' "$2" ;;
    *) return 1 ;;
  esac
}

get_cluster_nodes_info() {
  case $scenario in
    target-first)
      cat <<'EOF'
target-id 10.42.0.228:6379@16379,redis-shard-sxj-1.redis-shard-sxj-headless.default.svc.cluster.local myself,master - 0 0 0 connected
owner-id 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local master - 0 1 1 connected 0-5460
other-id 10.42.0.229:6379@16379,redis-shard-abc-0.redis-shard-abc-headless.default.svc.cluster.local master - 0 1 1 connected 5461-10922
EOF
      ;;
    disconnected)
      cat <<'EOF'
target-id 10.42.0.228:6379@16379,redis-shard-sxj-1.redis-shard-sxj-headless.default.svc.cluster.local myself,master - 0 0 0 connected
owner-id 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local master - 0 1 1 disconnected 0-5460
other-id 10.42.0.229:6379@16379,redis-shard-abc-0.redis-shard-abc-headless.default.svc.cluster.local master - 0 1 1 connected 5461-10922
EOF
      ;;
    failed)
      cat <<'EOF'
target-id 10.42.0.228:6379@16379,redis-shard-sxj-1.redis-shard-sxj-headless.default.svc.cluster.local myself,master - 0 0 0 connected
owner-id 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local master,fail - 0 1 1 connected 0-5460
other-id 10.42.0.229:6379@16379,redis-shard-abc-0.redis-shard-abc-headless.default.svc.cluster.local master - 0 1 1 connected 5461-10922
EOF
      ;;
    multiple)
      cat <<'EOF'
target-id 10.42.0.228:6379@16379,redis-shard-sxj-1.redis-shard-sxj-headless.default.svc.cluster.local myself,master - 0 0 0 connected
owner-a-id 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local master - 0 1 1 connected 0-2730
owner-b-id 10.42.0.230:6379@16379,redis-shard-sxj-2.redis-shard-sxj-headless.default.svc.cluster.local master - 0 1 1 connected 2731-5460
other-id 10.42.0.229:6379@16379,redis-shard-abc-0.redis-shard-abc-headless.default.svc.cluster.local master - 0 1 1 connected 5461-10922
EOF
      ;;
    *)
      printf 'unsupported scenario: %s\n' "$scenario" >&2
      return 2
      ;;
  esac
}

__SOURCED__=$script
# shellcheck source=/dev/null
source "$script"

CURRENT_SHARD_ADVERTISED_PORT=
CURRENT_SHARD_ADVERTISED_BUS_PORT=
CURRENT_SHARD_LB_ADVERTISED_PORT=
REDIS_CLUSTER_ALL_SHARDS_HOST_NETWORK_PORT=
ALL_SHARDS_COMPONENT_SHORT_NAMES=redis-shard-sxj,redis-shard-abc,redis-shard-def
CURRENT_SHARD_COMPONENT_NAME=redis-shard-sxj
CURRENT_SHARD_POD_NAME_LIST=redis-shard-sxj-0,redis-shard-sxj-1,redis-shard-sxj-2
CURRENT_SHARD_POD_FQDN_LIST=redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local,redis-shard-sxj-1.redis-shard-sxj-headless.default.svc.cluster.local,redis-shard-sxj-2.redis-shard-sxj-headless.default.svc.cluster.local
CLUSTER_NAMESPACE=default
SERVICE_PORT=6379
service_port=6379
CURRENT_POD_NAME=redis-shard-sxj-1
redis_announce_host_value=10.42.0.228
current_comp_primary_node=()
current_comp_primary_fail_node=()
current_comp_other_nodes=()
other_comp_primary_nodes=()
other_comp_primary_fail_nodes=()
other_comp_other_nodes=()

if [[ $mode == classify ]]; then
  get_current_comp_nodes_for_scale_out_replica \
    redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local 6379 >/dev/null

  printf 'family=%s\n' "$family"
  printf 'scenario=%s\n' "$scenario"
  printf 'initialized=%s\n' "${cluster_view_initialized:-false}"
  printf 'primary_count=%s\n' "${#current_comp_primary_node[@]}"
  printf 'primary=%s\n' "${current_comp_primary_node[*]:-}"
  printf 'fail_count=%s\n' "${#current_comp_primary_fail_node[@]}"
  printf 'fail=%s\n' "${current_comp_primary_fail_node[*]:-}"
  printf 'other=%s\n' "${current_comp_other_nodes[*]:-}"
  exit 0
fi

if [[ $mode != guard ]]; then
  printf 'unsupported mode: %s\n' "$mode" >&2
  exit 2
fi

check_redis_server_ready_with_retry() { return 0; }
get_target_pod_fqdn_from_pod_fqdn_vars() {
  printf 'redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local\n'
}
get_current_comp_nodes_for_scale_out_replica() {
  cluster_view_initialized=true
  current_comp_primary_node=()
  current_comp_primary_fail_node=()
  current_comp_other_nodes=(target)
  case $guard_scenario in
    multiple) current_comp_primary_node=(owner-a owner-b) ;;
    disconnected) current_comp_primary_fail_node=(disconnected-owner) ;;
    failed) current_comp_primary_fail_node=(failed-owner) ;;
  esac
}
shutdown_redis_server() { printf 'shutdown-called\n'; }
ensure_current_node_replication() { printf 'repair-called\n'; }
check_and_meet_other_primary_nodes() { printf 'mutate-called\n'; }

for guard_scenario in zero multiple disconnected failed; do
  set +e
  output=$(scale_redis_cluster_replica 2>&1)
  status=$?
  set -e
  expected_count=0
  [[ $guard_scenario == multiple ]] && expected_count=2
  [[ $status -ne 0 ]]
  [[ $output == *"Expected exactly one connected non-fail slot-owning primary for initialized shard redis-shard-sxj, found $expected_count"* ]]
  [[ $output == *"shutdown-called"* ]]
  [[ $output != *"repair-called"* ]]
  [[ $output != *"mutate-called"* ]]
  printf 'family=%s guard=%s status=%s mutation=0\n' "$family" "$guard_scenario" "$status"
done
