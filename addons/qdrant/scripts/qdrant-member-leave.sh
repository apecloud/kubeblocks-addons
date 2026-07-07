#!/usr/bin/env bash

qdrant_select_target_peer_id() {
  local cluster_info="$1"
  local leave_peer_id="$2"
  local leader_peer_id="$3"
  local jq_bin="${JQ:-jq}"

  if [ -n "$leader_peer_id" ] && [ "$leader_peer_id" != "null" ] && [ "$leader_peer_id" != "$leave_peer_id" ]; then
    echo "$leader_peer_id"
    return 0
  fi

  echo "$cluster_info" | "$jq_bin" -r \
    --arg leave "$leave_peer_id" \
    '.result.peers
     | to_entries
     | map(select(.key != $leave))
     | .[0].key // ""'
}

qdrant_peer_id_for_pod() {
  local cluster_info="$1"
  local pod_name="$2"
  local jq_bin="${JQ:-jq}"

  echo "$cluster_info" | "$jq_bin" -r \
    --arg name "$pod_name" \
    '.result.peers | to_entries[] | select(.value.uri | contains($name)) | .key'
}

qdrant_peer_exists() {
  local cluster_info="$1"
  local peer_id="$2"
  local jq_bin="${JQ:-jq}"

  echo "$cluster_info" | "$jq_bin" -e \
    --arg peer "$peer_id" \
    '.result.peers | has($peer)' >/dev/null
}

qdrant_shard_transfer_exists() {
  local collection_cluster_info="$1"
  local shard_id="$2"
  local from_peer_id="$3"
  local jq_bin="${JQ:-jq}"

  echo "$collection_cluster_info" | "$jq_bin" -e \
    --argjson shard "$shard_id" \
    --argjson from "$from_peer_id" \
    '(.result.shard_transfers // [])
     | any(.shard_id == $shard and .from == $from)' >/dev/null
}

qdrant_shard_on_leaving_peer() {
  local collection_cluster_info="$1"
  local shard_id="$2"
  local peer_id="$3"
  local jq_bin="${JQ:-jq}"

  echo "$collection_cluster_info" | "$jq_bin" -e \
    --argjson shard "$shard_id" \
    --argjson peer "$peer_id" \
    '((.result.remote_shards // [])
      | any(.peer_id == $peer and .shard_id == $shard))
     or
     ((.result.local_shards // [])
      | any((.peer_id? // $peer) == $peer and .shard_id == $shard))' >/dev/null
}

qdrant_remaining_on_leaving_count() {
  local collection_cluster_info="$1"
  local peer_id="$2"
  local jq_bin="${JQ:-jq}"

  echo "$collection_cluster_info" | "$jq_bin" -r \
    --argjson peer "$peer_id" \
    '[
       (.result.remote_shards // [])[] | select(.peer_id == $peer)
     ] | length'
}

qdrant_transfers_from_leaving_count() {
  local collection_cluster_info="$1"
  local peer_id="$2"
  local jq_bin="${JQ:-jq}"

  echo "$collection_cluster_info" | "$jq_bin" -r \
    --argjson peer "$peer_id" \
    '[
       (.result.shard_transfers // [])[] | select(.from == $peer)
     ] | length'
}

qdrant_unique_lines() {
  awk 'NF && !seen[$0]++'
}

qdrant_control_uris_from_cluster_info() {
  local cluster_info="$1"
  local jq_bin="${JQ:-jq}"

  echo "$cluster_info" | "$jq_bin" -r \
    --arg name "$KB_LEAVE_MEMBER_POD_NAME" \
    '.result.peers
     | to_entries[]
     | select(.value.uri | contains($name) | not)
     | .value.uri
     | sub(":6335/?$"; ":6333")'
}

qdrant_collection_cluster_info_from_uri() {
  local control_endpoint_uri="$1"
  local col_name="$2"

  qdrant_curl -sf --max-time "${QDRANT_MEMBER_LEAVE_CURL_TIMEOUT:-5}" \
    "${control_endpoint_uri}/collections/${col_name}/cluster"
}

qdrant_collection_cluster_info_from_control() {
  local col_name="$1"

  qdrant_collection_cluster_info_from_uri "$control_uri" "$col_name"
}

qdrant_collection_cluster_info_from_leaving() {
  local col_name="$1"

  qdrant_curl -sf --max-time "${QDRANT_MEMBER_LEAVE_CURL_TIMEOUT:-5}" \
    "${leave_peer_uri}/collections/${col_name}/cluster"
}

qdrant_leaving_shards_for_collection() {
  local col_name="$1"
  local col_cluster_info
  local control_endpoint_uri
  local control_endpoint_uris="${control_uris:-$control_uri}"
  local shard_ids=""
  local ids
  local jq_bin="${JQ:-jq}"

  col_cluster_info="$(qdrant_collection_cluster_info_from_leaving "$col_name" 2>/dev/null)" || col_cluster_info=""
  if [ -n "$col_cluster_info" ]; then
    ids="$(echo "$col_cluster_info" | "$jq_bin" -r '(.result.local_shards // [])[]? | .shard_id')"
    if [ -n "$ids" ]; then
      shard_ids="${shard_ids}${ids}
"
    fi
  else
    echo "INFO: leaving peer endpoint unavailable for ${col_name}; using control endpoint state" >&2
  fi

  for control_endpoint_uri in $control_endpoint_uris; do
    col_cluster_info="$(qdrant_collection_cluster_info_from_uri "$control_endpoint_uri" "$col_name")" || return 1
    ids="$(echo "$col_cluster_info" | "$jq_bin" -r \
      --argjson peer "$leave_peer_id" \
      '(.result.remote_shards // [])[]? | select(.peer_id == $peer) | .shard_id')"
    if [ -n "$ids" ]; then
      shard_ids="${shard_ids}${ids}
"
    fi
  done

  printf "%s" "$shard_ids" | qdrant_unique_lines
}

qdrant_remaining_on_leaving_count_from_all_views() {
  local col_name="$1"
  local col_cluster_info
  local control_endpoint_uri
  local control_endpoint_uris="${control_uris:-$control_uri}"
  local shard_ids=""
  local ids
  local jq_bin="${JQ:-jq}"

  col_cluster_info="$(qdrant_collection_cluster_info_from_leaving "$col_name" 2>/dev/null)" || col_cluster_info=""
  if [ -n "$col_cluster_info" ]; then
    ids="$(echo "$col_cluster_info" | "$jq_bin" -r '(.result.local_shards // [])[]? | .shard_id')"
    if [ -n "$ids" ]; then
      shard_ids="${shard_ids}${ids}
"
    fi
  fi

  for control_endpoint_uri in $control_endpoint_uris; do
    col_cluster_info="$(qdrant_collection_cluster_info_from_uri "$control_endpoint_uri" "$col_name")" || return 1
    ids="$(echo "$col_cluster_info" | "$jq_bin" -r \
      --argjson peer "$leave_peer_id" \
      '(.result.remote_shards // [])[]? | select(.peer_id == $peer) | .shard_id')"
    if [ -n "$ids" ]; then
      shard_ids="${shard_ids}${ids}
"
    fi
  done

  printf "%s" "$shard_ids" | qdrant_unique_lines | wc -l | tr -d ' '
}

qdrant_transfers_from_leaving_count_from_all_controls() {
  local col_name="$1"
  local col_cluster_info
  local control_endpoint_uri
  local control_endpoint_uris="${control_uris:-$control_uri}"
  local transfer_ids=""
  local ids
  local jq_bin="${JQ:-jq}"

  for control_endpoint_uri in $control_endpoint_uris; do
    col_cluster_info="$(qdrant_collection_cluster_info_from_uri "$control_endpoint_uri" "$col_name")" || return 1
    ids="$(echo "$col_cluster_info" | "$jq_bin" -r \
      --argjson peer "$leave_peer_id" \
      '(.result.shard_transfers // [])[]?
       | select(.from == $peer)
       | "\(.shard_id):\(.from):\(.to)"')"
    if [ -n "$ids" ]; then
      transfer_ids="${transfer_ids}${ids}
"
    fi
  done

  printf "%s" "$transfer_ids" | qdrant_unique_lines | wc -l | tr -d ' '
}

qdrant_collection_cluster_info_for_leaving_shard() {
  local col_name="$1"
  local shard_id="$2"
  local col_cluster_info
  local fallback_info=""
  local control_endpoint_uri
  local control_endpoint_uris="${control_uris:-$control_uri}"

  for control_endpoint_uri in $control_endpoint_uris; do
    col_cluster_info="$(qdrant_collection_cluster_info_from_uri "$control_endpoint_uri" "$col_name")" || return 1
    if [ -z "$fallback_info" ]; then
      fallback_info="$col_cluster_info"
    fi
    if qdrant_shard_transfer_exists "$col_cluster_info" "$shard_id" "$leave_peer_id" ||
        qdrant_shard_on_leaving_peer "$col_cluster_info" "$shard_id" "$leave_peer_id"; then
      printf "%s\n" "$col_cluster_info"
      return 0
    fi
  done

  printf "%s\n" "$fallback_info"
}

qdrant_submit_shard_move_if_needed() {
  local col_name="$1"
  local shard_id="$2"
  local col_cluster_info="$3"
  local move_payload

  if qdrant_shard_transfer_exists "$col_cluster_info" "$shard_id" "$leave_peer_id"; then
    echo "INFO: shard ${shard_id} in ${col_name} is already moving from peer ${leave_peer_id}"
    return 0
  fi

  if ! qdrant_shard_on_leaving_peer "$col_cluster_info" "$shard_id" "$leave_peer_id"; then
    echo "INFO: shard ${shard_id} in ${col_name} is already off peer ${leave_peer_id}"
    return 0
  fi

  echo "INFO: move shard ${shard_id} in ${col_name} from peer ${leave_peer_id} to peer ${target_peer_id}"
  move_payload="$(printf '{"move_shard":{"shard_id":%s,"to_peer_id":%s,"from_peer_id":%s}}' \
    "$shard_id" "$target_peer_id" "$leave_peer_id")"

  if qdrant_curl -sf --max-time "${QDRANT_MEMBER_LEAVE_CURL_TIMEOUT:-5}" \
      -X POST -H "Content-Type: application/json" \
      -d "$move_payload" \
      "${control_uri}/collections/${col_name}/cluster"; then
    return 0
  fi

  echo "WARN: move_shard request failed for shard ${shard_id} in ${col_name}; checking current state"
  col_cluster_info="$(qdrant_collection_cluster_info_for_leaving_shard "$col_name" "$shard_id")" || return 1
  if qdrant_shard_transfer_exists "$col_cluster_info" "$shard_id" "$leave_peer_id"; then
    echo "INFO: shard ${shard_id} in ${col_name} is already moving after failed submit"
    return 0
  fi
  if ! qdrant_shard_on_leaving_peer "$col_cluster_info" "$shard_id" "$leave_peer_id"; then
    echo "INFO: shard ${shard_id} in ${col_name} moved off peer ${leave_peer_id} after failed submit"
    return 0
  fi

  echo "ERROR: failed to initiate shard ${shard_id} move in ${col_name}"
  return 1
}

qdrant_wait_for_collection_drained() {
  local col_name="$1"
  local deadline
  local remaining
  local transfers

  deadline="${qdrant_member_leave_deadline:-$((SECONDS + ${QDRANT_MEMBER_LEAVE_WAIT_SECONDS:-20}))}"
  while true; do
    remaining="$(qdrant_remaining_on_leaving_count_from_all_views "$col_name")" || return 1
    transfers="$(qdrant_transfers_from_leaving_count_from_all_controls "$col_name")" || return 1

    if [ "$remaining" = "0" ] && [ "$transfers" = "0" ]; then
      echo "INFO: all shards in collection ${col_name} moved off peer ${leave_peer_id}"
      return 0
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "ERROR: timed out waiting for ${col_name} to drain from peer ${leave_peer_id}; remaining=${remaining}, transfers=${transfers}"
      return 1
    fi

    echo "INFO: waiting for ${col_name} drain from peer ${leave_peer_id}; remaining=${remaining}, transfers=${transfers}"
    sleep "${QDRANT_MEMBER_LEAVE_POLL_SECONDS:-2}"
  done
}

qdrant_move_shards() {
  local cols
  local col_count
  local col_names
  local col_name
  local leave_shard_ids
  local shard_id
  local col_cluster_info

  if ! cols="$(qdrant_curl -sf --max-time "${QDRANT_MEMBER_LEAVE_CURL_TIMEOUT:-5}" "${control_uri}/collections")"; then
    echo "ERROR: failed to list collections from ${control_uri}"
    return 1
  fi

  col_count="$(echo "$cols" | "$JQ" -r '.result.collections | length')"
  if [ "$col_count" -eq 0 ]; then
    echo "INFO: no collections found in the cluster"
    return 0
  fi

  col_names="$(echo "$cols" | "$JQ" -r '.result.collections[].name')"
  for col_name in $col_names; do
    leave_shard_ids="$(qdrant_leaving_shards_for_collection "$col_name")" || return 1
    if [ -z "$leave_shard_ids" ]; then
      echo "INFO: no shards on leaving peer for collection ${col_name}"
      qdrant_wait_for_collection_drained "$col_name" || return 1
      continue
    fi

    for shard_id in $leave_shard_ids; do
      col_cluster_info="$(qdrant_collection_cluster_info_for_leaving_shard "$col_name" "$shard_id")" || return 1
      qdrant_submit_shard_move_if_needed "$col_name" "$shard_id" "$col_cluster_info" || return 1
    done

    qdrant_wait_for_collection_drained "$col_name" || return 1
  done
}

qdrant_remove_peer() {
  local latest_cluster_info

  latest_cluster_info="$(qdrant_curl -sf --max-time "${QDRANT_MEMBER_LEAVE_CURL_TIMEOUT:-5}" "${control_uri}/cluster")" || return 1
  if ! qdrant_peer_exists "$latest_cluster_info" "$leave_peer_id"; then
    echo "INFO: peer ${leave_peer_id} is already absent from cluster"
    return 0
  fi

  echo "INFO: remove peer ${leave_peer_id} from cluster"
  if qdrant_curl -sf --max-time "${QDRANT_MEMBER_LEAVE_CURL_TIMEOUT:-5}" \
      -XDELETE "${control_uri}/cluster/peer/${leave_peer_id}"; then
    echo "INFO: peer ${leave_peer_id} removed successfully"
    return 0
  fi

  latest_cluster_info="$(qdrant_curl -sf --max-time "${QDRANT_MEMBER_LEAVE_CURL_TIMEOUT:-5}" "${control_uri}/cluster")" || return 1
  if ! qdrant_peer_exists "$latest_cluster_info" "$leave_peer_id"; then
    echo "INFO: peer ${leave_peer_id} is absent after failed delete response"
    return 0
  fi

  echo "ERROR: failed to remove peer ${leave_peer_id} from cluster"
  return 1
}

qdrant_load_common_library() {
  common_library_file="/qdrant/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

qdrant_configure_client() {
  QDRANT_CURL_BIN="${QDRANT_CURL_BIN:-/qdrant/tools/curl}"
  export QDRANT_CURL_BIN
  JQ="${JQ:-/qdrant/tools/jq}"

  if [ "${TLS_ENABLED:-}" = "true" ]; then
    SCHEME="https"
    CURL_TLS="-k"
  else
    SCHEME="http"
    CURL_TLS=""
  fi
}

qdrant_select_control_endpoint() {
  local cluster_info="$1"
  local surviving_control_uri

  surviving_control_uri="$(echo "$cluster_info" | "$JQ" -r \
    --arg name "$KB_LEAVE_MEMBER_POD_NAME" \
    '.result.peers
     | to_entries
     | map(select(.value.uri | contains($name) | not))
     | .[0].value.uri // ""
     | sub(":6335/?$"; ":6333")')"
  if [ -n "$surviving_control_uri" ]; then
    control_uri="$surviving_control_uri"
  fi
}

qdrant_load_cluster_state() {
  local peers_type
  local peer_count

  control_host="$(qdrant_bootstrap_service_host)"
  control_uri="${SCHEME}://${control_host}:6333"

  if ! cluster_info="$(qdrant_curl -sf --max-time "${QDRANT_MEMBER_LEAVE_CURL_TIMEOUT:-5}" "${control_uri}/cluster")" ||
      [ -z "$cluster_info" ]; then
    echo "ERROR: failed to query cluster info from ${control_uri}"
    return 1
  fi

  peers_type="$(echo "$cluster_info" | "$JQ" -r '.result.peers | type' 2>/dev/null)"
  if [ $? -ne 0 ] || [ "$peers_type" != "object" ]; then
    echo "ERROR: cluster response missing or malformed .result.peers (type=${peers_type:-null})"
    return 1
  fi

  qdrant_select_control_endpoint "$cluster_info"
  if ! cluster_info="$(qdrant_curl -sf --max-time "${QDRANT_MEMBER_LEAVE_CURL_TIMEOUT:-5}" "${control_uri}/cluster")" ||
      [ -z "$cluster_info" ]; then
    echo "ERROR: failed to query cluster info from selected control peer ${control_uri}"
    return 1
  fi
  control_uris="$(qdrant_control_uris_from_cluster_info "$cluster_info")"
  if [ -z "$control_uris" ]; then
    echo "ERROR: no surviving qdrant control endpoint is available for leaving peer ${KB_LEAVE_MEMBER_POD_NAME}"
    return 1
  fi
  control_uri="$(printf "%s\n" "$control_uris" | head -n 1)"

  echo "INFO: KB_LEAVE_MEMBER_POD_NAME=${KB_LEAVE_MEMBER_POD_NAME}"
  echo "INFO: KB_LEAVE_MEMBER_POD_FQDN=${KB_LEAVE_MEMBER_POD_FQDN}"
  echo "INFO: cluster peers:"
  echo "$cluster_info" | "$JQ" -r '.result.peers | to_entries[] | "INFO: \(.key): \(.value.uri)"'

  leave_peer_id="$(qdrant_peer_id_for_pod "$cluster_info" "$KB_LEAVE_MEMBER_POD_NAME")"
  if [ -z "$leave_peer_id" ]; then
    echo "INFO: member ${KB_LEAVE_MEMBER_POD_NAME} is not in the cluster"
    return 10
  fi

  peer_count="$(echo "$leave_peer_id" | wc -l | tr -d ' ')"
  if [ "$peer_count" -ne 1 ]; then
    echo "ERROR: expected 1 matching peer for ${KB_LEAVE_MEMBER_POD_NAME}, found ${peer_count}"
    return 1
  fi
  if ! [[ "$leave_peer_id" =~ ^[0-9]+$ ]]; then
    echo "ERROR: leave_peer_id '${leave_peer_id}' is not a valid numeric peer ID"
    return 1
  fi

  leader_peer_id="$(echo "$cluster_info" | "$JQ" -r .result.raft_info.leader)"
  target_peer_id="$(qdrant_select_target_peer_id "$cluster_info" "$leave_peer_id" "$leader_peer_id")"
  if [ -z "$target_peer_id" ]; then
    echo "ERROR: no surviving qdrant peer is available as shard move target for leaving peer ${leave_peer_id}"
    return 1
  fi

  leave_peer_uri="${SCHEME}://${KB_LEAVE_MEMBER_POD_FQDN}:6333"
  echo "INFO: leaving peer=${KB_LEAVE_MEMBER_POD_NAME}, peer_id=${leave_peer_id}, uri=${leave_peer_uri}"
  echo "INFO: leader peer_id=${leader_peer_id}"
  echo "INFO: target peer_id=${target_peer_id}"
  echo "INFO: control endpoint=${control_uri}"
  echo "INFO: control endpoints:"
  printf "%s\n" "$control_uris" | sed 's/^/INFO: - /'
}

qdrant_leave_member() {
  echo "INFO: scaling in: move local shards and remove peer from cluster"
  qdrant_member_leave_deadline=$((SECONDS + ${QDRANT_MEMBER_LEAVE_WAIT_SECONDS:-20}))
  qdrant_move_shards
  qdrant_remove_peer
}

qdrant_member_leave_main() {
  set -o errtrace
  set -o errexit
  set -o nounset
  set -o pipefail

  echo "INFO: memberLeave action started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ "${QDRANT_MEMBER_LEAVE_XTRACE:-}" = "true" ]; then
    set -x
  fi
  qdrant_load_common_library
  qdrant_configure_client

  set +o errexit
  qdrant_load_cluster_state
  rc=$?
  set -o errexit
  if [ "$rc" -eq 10 ]; then
    exit 0
  fi
  if [ "$rc" -ne 0 ]; then
    exit "$rc"
  fi

  (
    flock -n -x 9
    if [ $? -ne 0 ]; then
      echo "ERROR: memberLeave action is already running for this pod"
      exit 1
    fi
    qdrant_leave_member
  ) 9>/var/lock/qdrant-leave-member-lock
}

if [ "${QDRANT_MEMBER_LEAVE_UNIT_TEST:-}" = "true" ]; then
  return 0 2>/dev/null || exit 0
fi

qdrant_member_leave_main "$@"
