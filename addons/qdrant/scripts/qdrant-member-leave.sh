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
JQ_BIN="${QDRANT_JQ_BIN:-/qdrant/tools/jq}"
if [ ! -x "$JQ_BIN" ]; then
  JQ_BIN=jq
fi

if [ "${TLS_ENABLED:-}" = "true" ]; then
  SCHEME="https"
  CURL_TLS="-k"
else
  SCHEME="http"
  CURL_TLS=""
fi

current_peer_uri=${SCHEME}://${current_pod_fqdn}:6333

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

remove_peer() {
  current_cluster_info="$(qdrant_curl -sf "${current_peer_uri}/cluster")"
  leave_peer_id="$(leaving_peer_id_from_cluster "$current_cluster_info")"

  if [ -z "$leave_peer_id" ] || [ "$leave_peer_id" = "null" ]; then
    echo "member ${KB_LEAVE_MEMBER_POD_NAME} is not in the qdrant cluster"
    return 0
  fi

  echo "remove peer ${leave_peer_id} for member ${KB_LEAVE_MEMBER_POD_NAME} from cluster"
  if qdrant_curl -sf -XDELETE "${current_peer_uri}/cluster/peer/${leave_peer_id}?force=true"; then
    return 0
  fi

  current_cluster_info="$(qdrant_curl -sf "${current_peer_uri}/cluster")"
  if ! printf "%s" "$current_cluster_info" | "$JQ_BIN" -e --arg peer_id "$leave_peer_id" '.result.peers | has($peer_id)' >/dev/null; then
    echo "peer ${leave_peer_id} is already removed"
    return 0
  fi

  echo "failed to remove peer ${leave_peer_id}"
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
