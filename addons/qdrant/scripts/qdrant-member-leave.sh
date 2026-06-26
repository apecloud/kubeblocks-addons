#!/usr/bin/env bash

set -euo pipefail

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/qdrant/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

load_common_library
CURRENT_POD_NAME="${CURRENT_POD_NAME:-${HOSTNAME:-}}"
if [ -z "$CURRENT_POD_NAME" ]; then
  echo "CURRENT_POD_NAME is required"
  exit 1
fi
current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$QDRANT_POD_FQDN_LIST" "$CURRENT_POD_NAME")
if [ -z "$current_pod_fqdn" ]; then
  current_pod_fqdn="${QDRANT_POD_FQDN_LIST%%,*}"
fi
if [ -z "$current_pod_fqdn" ]; then
  echo "failed to resolve a live qdrant peer from QDRANT_POD_FQDN_LIST"
  exit 1
fi
JQ_BIN="${QDRANT_JQ_BIN:-/qdrant/tools/jq}"
if [ ! -x "$JQ_BIN" ]; then
  JQ_BIN=jq
fi
MEMBER_LEAVE_DRAIN_WAIT_SECONDS="${QDRANT_MEMBER_LEAVE_DRAIN_WAIT_SECONDS:-45}"
MEMBER_LEAVE_DRAIN_POLL_SECONDS="${QDRANT_MEMBER_LEAVE_DRAIN_POLL_SECONDS:-5}"
MEMBER_LEAVE_TRANSFER_METHOD="${QDRANT_MEMBER_LEAVE_TRANSFER_METHOD:-stream_records}"

if [ "${TLS_ENABLED:-}" = "true" ]; then
  SCHEME="https"
  CURL_TLS="-k"
else
  SCHEME="http"
  CURL_TLS=""
fi

current_peer_uri=${SCHEME}://${current_pod_fqdn}:6333

now_seconds() {
  date +%s
}

deadline_after() {
  echo $(( $(now_seconds) + "$1" ))
}

leaving_peer_filter() {
  "$JQ_BIN" -r \
    --arg pod "$KB_LEAVE_MEMBER_POD_NAME" \
    --arg fqdn "${KB_LEAVE_MEMBER_POD_FQDN:-}" \
    '
      .result.peers
      | to_entries[]
      | select(
          (.value.uri | contains("://" + $pod + "."))
          or ($fqdn != "" and (.value.uri | contains("://" + $fqdn)))
        )
      | .key
    '
}

leaving_peer_id_from_cluster() {
  printf "%s" "$1" | leaving_peer_filter | head -n 1
}

is_leaving_peer_removed() {
  local current_cluster_info leave_peer_id

  if ! current_cluster_info="$(qdrant_curl -sf "${current_peer_uri}/cluster")"; then
    echo "failed to query qdrant cluster while checking member ${KB_LEAVE_MEMBER_POD_NAME}"
    return 1
  fi

  leave_peer_id="$(leaving_peer_id_from_cluster "$current_cluster_info")"
  [ -z "$leave_peer_id" ] || [ "$leave_peer_id" = "null" ]
}

list_collections() {
  qdrant_curl -sf "${current_peer_uri}/collections" | "$JQ_BIN" -r '.result.collections[].name // empty'
}

collection_cluster_info() {
  local collection="$1"

  qdrant_curl -sf "${current_peer_uri}/collections/${collection}/cluster"
}

drain_operations_for_collection() {
  local leave_peer_id="$1"
  local current_cluster_info="$2"
  local collection_info="$3"

  printf "%s" "$collection_info" | "$JQ_BIN" -c \
    --arg leave_peer_id "$leave_peer_id" \
    --arg desired_pods "${QDRANT_POD_NAME_LIST:-}" \
    --arg method "$MEMBER_LEAVE_TRANSFER_METHOD" \
    --argjson current_cluster "$current_cluster_info" '
      def peer_num($id): ($id | tonumber);
      def shard_key_value: if has("shard_key") then .shard_key else null end;
      def same_shard($shard):
        .shard_id == $shard.shard_id and ((.shard_key // null) == ($shard.shard_key // null));
      def with_shard_key($object; $shard):
        if ($shard.shard_key // null) == null then $object else $object + {shard_key: $shard.shard_key} end;
      def desired_peer($uri):
        ($desired_pods | split(",") | map(select(. != ""))) as $pods
        | if ($pods | length) == 0 then true else any($pods[]; $uri | contains("://" + . + ".")) end;

      . as $info
      | ($current_cluster.result.peers
        | to_entries
        | map(select(.key != $leave_peer_id))
        | map(select(desired_peer(.value.uri)))
        | map({id: .key, uri: .value.uri, preferred: desired_peer(.value.uri)})
        | sort_by(if .preferred then 0 else 1 end, (.id | tonumber? // .id))) as $candidate_peers
      | ([
          if (($info.result.peer_id | tostring) == $leave_peer_id) then
            $info.result.local_shards[]? | {shard_id, shard_key: shard_key_value}
          else empty end,
          $info.result.remote_shards[]?
            | select((.peer_id | tostring) == $leave_peer_id)
            | {shard_id, shard_key: shard_key_value}
        ] | unique_by([.shard_id, (.shard_key // "")]))[] as $shard
      | ([
          if (($info.result.peer_id | tostring) != $leave_peer_id) then
            $info.result.local_shards[]?
              | select(same_shard($shard))
              | {peer_id: ($info.result.peer_id | tostring), state: (.state // "Active")}
          else empty end,
          $info.result.remote_shards[]?
            | select((.peer_id | tostring) != $leave_peer_id)
            | select(same_shard($shard))
            | {peer_id: (.peer_id | tostring), state: (.state // "Active")}
        ] | unique_by(.peer_id)) as $other_replicas
      | ([$other_replicas[] | select(.state == "Active") | .peer_id] | unique) as $active_replica_owners
      | ([$other_replicas[] | .peer_id] | unique) as $all_replica_owners
      | ([
          $info.result.shard_transfers[]?
            | select(((.from | tostring) == $leave_peer_id) or ((.to | tostring) == $leave_peer_id))
            | select(.shard_id == $shard.shard_id and ((.shard_key // null) == ($shard.shard_key // null)))
        ] | length) as $transfer_count
      | if $transfer_count > 0 then
          {operation: "wait", shard: $shard}
        elif ($active_replica_owners | length) > 0 then
          {
            operation: "drop_replica",
            payload: {
              drop_replica: with_shard_key({
                shard_id: $shard.shard_id,
                peer_id: peer_num($leave_peer_id)
              }; $shard)
            }
          }
        else
          ($candidate_peers | map(select(.id as $id | ($all_replica_owners | index($id) | not))) | .[0]) as $target
          | if $target == null then
              {operation: "error", message: "no target peer available for shard", shard: $shard}
            else
              {
                operation: "move_shard",
                payload: {
                  move_shard: with_shard_key({
                    shard_id: $shard.shard_id,
                    from_peer_id: peer_num($leave_peer_id),
                    to_peer_id: peer_num($target.id),
                    method: $method
                  }; $shard)
                }
              }
            end
        end
    '
}

collection_peer_shard_count() {
  local leave_peer_id="$1"
  local collection_info="$2"

  printf "%s" "$collection_info" | "$JQ_BIN" -r --arg leave_peer_id "$leave_peer_id" '
    . as $info
    | [
        if (($info.result.peer_id | tostring) == $leave_peer_id) then
          $info.result.local_shards[]?
        else empty end,
        $info.result.remote_shards[]? | select((.peer_id | tostring) == $leave_peer_id)
      ]
    | length
  '
}

collection_peer_transfer_count() {
  local leave_peer_id="$1"
  local collection_info="$2"

  printf "%s" "$collection_info" | "$JQ_BIN" -r --arg leave_peer_id "$leave_peer_id" '
    [
      .result.shard_transfers[]?
      | select(((.from | tostring) == $leave_peer_id) or ((.to | tostring) == $leave_peer_id))
    ]
    | length
  '
}

apply_drain_operation() {
  local collection="$1"
  local operation="$2"
  local operation_type
  local payload

  operation_type="$(printf "%s" "$operation" | "$JQ_BIN" -r '.operation')"
  case "$operation_type" in
    wait)
      echo "wait for existing shard transfer in collection ${collection}"
      ;;
    move_shard|drop_replica)
      payload="$(printf "%s" "$operation" | "$JQ_BIN" -c '.payload')"
      echo "apply ${operation_type} for collection ${collection}: ${payload}"
      qdrant_curl -sf -XPOST "${current_peer_uri}/collections/${collection}/cluster?timeout=30" \
        -H "Content-Type: application/json" \
        -d "$payload" >/dev/null
      ;;
    error)
      printf "%s" "$operation" | "$JQ_BIN" -r '.message'
      return 1
      ;;
  esac
}

wait_for_peer_drain() {
  local leave_peer_id="$1"
  local deadline
  local collection
  local collection_info
  local shard_count
  local transfer_count
  local remaining_count

  deadline="$(deadline_after "$MEMBER_LEAVE_DRAIN_WAIT_SECONDS")"
  while [ "$(now_seconds)" -lt "$deadline" ]; do
    remaining_count=0
    for collection in $(list_collections); do
      collection_info="$(collection_cluster_info "$collection")"
      shard_count="$(collection_peer_shard_count "$leave_peer_id" "$collection_info")"
      transfer_count="$(collection_peer_transfer_count "$leave_peer_id" "$collection_info")"
      remaining_count=$((remaining_count + shard_count + transfer_count))
    done
    if [ "$remaining_count" -eq 0 ]; then
      return 0
    fi
    echo "peer ${leave_peer_id} still has ${remaining_count} shard(s) or transfer(s), waiting..."
    sleep "$MEMBER_LEAVE_DRAIN_POLL_SECONDS"
  done

  return 1
}

drain_peer_shards() {
  local leave_peer_id="$1"
  local current_cluster_info="$2"
  local collection
  local collection_info
  local operation

  echo "drain qdrant shards from peer ${leave_peer_id}"
  for collection in $(list_collections); do
    collection_info="$(collection_cluster_info "$collection")"
    while IFS= read -r operation; do
      [ -n "$operation" ] || continue
      apply_drain_operation "$collection" "$operation"
    done <<EOF
$(drain_operations_for_collection "$leave_peer_id" "$current_cluster_info" "$collection_info")
EOF
  done

  if wait_for_peer_drain "$leave_peer_id"; then
    echo "peer ${leave_peer_id} has no qdrant shards or transfers"
    return 0
  fi

  echo "peer ${leave_peer_id} still has qdrant shards or transfers, retry member leave later"
  return 1
}

remove_peer() {
  local current_cluster_info leave_peer_id

  current_cluster_info="$(qdrant_curl -sf "${current_peer_uri}/cluster")"
  leave_peer_id="$(leaving_peer_id_from_cluster "$current_cluster_info")"

  if [ -z "$leave_peer_id" ] || [ "$leave_peer_id" = "null" ]; then
    echo "member ${KB_LEAVE_MEMBER_POD_NAME} is not in the qdrant cluster"
    return 0
  fi

  drain_peer_shards "$leave_peer_id" "$current_cluster_info"

  echo "remove peer ${leave_peer_id} for member ${KB_LEAVE_MEMBER_POD_NAME} from cluster"
  if qdrant_curl -sf -XDELETE "${current_peer_uri}/cluster/peer/${leave_peer_id}"; then
    return 0
  fi

  current_cluster_info="$(qdrant_curl -sf "${current_peer_uri}/cluster")"
  if ! printf "%s" "$current_cluster_info" | "$JQ_BIN" -e --arg peer_id "$leave_peer_id" '.result.peers | has($peer_id)' >/dev/null; then
    echo "peer ${leave_peer_id} is already removed"
    return 0
  fi

  echo "failed to remove peer ${leave_peer_id}; it may still own shards"
  return 1
}

leave_member() {
  echo "scaling in, remove qdrant peer membership for ${KB_LEAVE_MEMBER_POD_NAME}"
  remove_peer
}

leave_member_lock_file="/var/lock/qdrant-leave-member-${KB_LEAVE_MEMBER_POD_NAME}.lock"

# lock file to prevent duplicate leave_member for the same pod without blocking the lifecycle action
(
  if ! flock -n -x 9; then
    echo "qdrant member leave is already running for ${KB_LEAVE_MEMBER_POD_NAME}"
    if is_leaving_peer_removed; then
      echo "member ${KB_LEAVE_MEMBER_POD_NAME} is already removed from the qdrant cluster"
      exit 0
    fi
    echo "member ${KB_LEAVE_MEMBER_POD_NAME} is still in the qdrant cluster, retry member leave later"
    exit 1
  fi
  leave_member
) 9>"${leave_member_lock_file}"
