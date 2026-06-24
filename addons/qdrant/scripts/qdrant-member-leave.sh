#!/usr/bin/env bash

set -x
set -o errtrace
set -o nounset
set -o pipefail

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/qdrant/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

load_common_library

CURL=/qdrant/tools/curl
JQ=/qdrant/tools/jq

if [ "${TLS_ENABLED:-}" = "true" ]; then
  SCHEME="https"
  CURL_TLS="-k"
else
  SCHEME="http"
  CURL_TLS=""
fi

# Use the first live pod from QDRANT_POD_FQDN_LIST as the control plane endpoint.
# The leaving pod may already be shutting down; admin operations (move shard,
# DELETE peer) must go through a known-live peer.
control_fqdn=$(echo "$QDRANT_POD_FQDN_LIST" | tr ',' '\n' | head -1)
if [ -z "$control_fqdn" ]; then
  echo "ERROR: QDRANT_POD_FQDN_LIST is empty"
  exit 1
fi
control_uri=${SCHEME}://${control_fqdn}:6333

# Query cluster state from a live peer.
cluster_info=$($CURL $CURL_TLS -sf --max-time 10 ${control_uri}/cluster)
if [ $? -ne 0 ] || [ -z "$cluster_info" ]; then
  echo "ERROR: failed to query cluster info from ${control_uri}"
  exit 1
fi

# Validate cluster response has a parseable peers object.
peers_type=$(echo "$cluster_info" | $JQ -r '.result.peers | type' 2>/dev/null)
if [ $? -ne 0 ] || [ "$peers_type" != "object" ]; then
  echo "ERROR: cluster response missing or malformed .result.peers (type=${peers_type:-null})"
  exit 1
fi

# Log peer URIs for diagnosis before attempting match.
echo "KB_LEAVE_MEMBER_POD_NAME=${KB_LEAVE_MEMBER_POD_NAME}"
echo "KB_LEAVE_MEMBER_POD_FQDN=${KB_LEAVE_MEMBER_POD_FQDN}"
peer_uris=$(echo "$cluster_info" | $JQ -r '.result.peers | to_entries[] | "\(.key): \(.value.uri)"')
echo "cluster peers:"
echo "$peer_uris"

# Find the leaving peer's ID by matching KB_LEAVE_MEMBER_POD_NAME in peer URIs.
# Two-step: first confirm peers is valid (above), then match. Only "valid peers +
# zero matches" is idempotent exit 0; parse failures always exit 1.
leave_peer_id=$(echo "$cluster_info" | $JQ -r \
  --arg name "$KB_LEAVE_MEMBER_POD_NAME" \
  '.result.peers | to_entries[] | select(.value.uri | contains($name)) | .key')
jq_rc=$?

if [ $jq_rc -ne 0 ]; then
  echo "ERROR: jq failed while searching for ${KB_LEAVE_MEMBER_POD_NAME} in peers (rc=${jq_rc})"
  exit 1
fi

if [ -z "$leave_peer_id" ]; then
  echo "member ${KB_LEAVE_MEMBER_POD_NAME} is not in the cluster (not found in peer URIs)"
  exit 0
fi

# Guard against multiple matches or non-numeric peer ID.
peer_count=$(echo "$leave_peer_id" | wc -l | tr -d ' ')
if [ "$peer_count" -ne 1 ]; then
  echo "ERROR: expected 1 matching peer for ${KB_LEAVE_MEMBER_POD_NAME}, found ${peer_count}"
  exit 1
fi
if ! [[ "$leave_peer_id" =~ ^[0-9]+$ ]]; then
  echo "ERROR: leave_peer_id '${leave_peer_id}' is not a valid numeric peer ID"
  exit 1
fi

echo "leaving peer: ${KB_LEAVE_MEMBER_POD_NAME}, peer_id=${leave_peer_id}"
leader_peer_id=$(echo "$cluster_info" | $JQ -r .result.raft_info.leader)
echo "leader peer_id=${leader_peer_id}"

# The leaving peer's HTTP endpoint for shard queries. KB calls memberLeave
# before pod termination, so this should be reachable.
leave_peer_uri=${SCHEME}://${KB_LEAVE_MEMBER_POD_FQDN}:6333

move_shards() {
    local cols col_count col_names

    cols=$($CURL $CURL_TLS -sf ${control_uri}/collections)
    if [ $? -ne 0 ]; then
      echo "ERROR: failed to list collections from ${control_uri}"
      return 1
    fi

    col_count=$(echo ${cols} | $JQ -r '.result.collections | length')
    if [[ ${col_count} -eq 0 ]]; then
        echo "no collections found in the cluster"
        return
    fi

    col_names=$(echo ${cols} | $JQ -r '.result.collections[].name')
    for col_name in ${col_names}; do
        # Query the leaving peer for its local shards (still alive during memberLeave).
        local col_cluster_info
        col_cluster_info=$($CURL $CURL_TLS -sf ${leave_peer_uri}/collections/${col_name}/cluster)
        if [ $? -ne 0 ]; then
          echo "ERROR: failed to get collection cluster info from leaving peer for ${col_name}"
          return 1
        fi

        local leave_shard_ids
        leave_shard_ids=$(echo ${col_cluster_info} | $JQ -r '.result.local_shards[].shard_id')
        if [ -z "${leave_shard_ids}" ]; then
            echo "no local shards on leaving peer for collection ${col_name}"
            continue
        fi

        for shard_id in ${leave_shard_ids}; do
            echo "move shard ${shard_id} in ${col_name} from peer ${leave_peer_id} to peer ${leader_peer_id}"
            # Submit move_shard via control endpoint (cluster-wide API).
            $CURL $CURL_TLS -sf -X POST -H "Content-Type: application/json" \
                -d '{"move_shard":{"shard_id": '${shard_id}',"to_peer_id": '${leader_peer_id}',"from_peer_id": '${leave_peer_id}}}'' \
                ${control_uri}/collections/${col_name}/cluster
            if [ $? -ne 0 ]; then
              echo "ERROR: failed to initiate shard ${shard_id} move in ${col_name}"
              return 1
            fi
        done

        # Wait for all shards to finish moving off the leaving peer.
        while true; do
            col_cluster_info=$($CURL $CURL_TLS -sf ${leave_peer_uri}/collections/${col_name}/cluster 2>/dev/null) || true
            if [ -n "$col_cluster_info" ]; then
              leave_shard_ids=$(echo ${col_cluster_info} | $JQ -r '.result.local_shards[].shard_id')
              if [ -z "${leave_shard_ids}" ]; then
                  echo "all shards in collection ${col_name} have been moved"
                  break
              fi
            else
              # Leaving peer unreachable during transfer — verify from control endpoint.
              col_cluster_info=$($CURL $CURL_TLS -sf ${control_uri}/collections/${col_name}/cluster)
              if [ $? -ne 0 ]; then
                echo "ERROR: cannot check shard status for ${col_name} from either endpoint"
                return 1
              fi
              local remaining
              remaining=$(echo ${col_cluster_info} | $JQ -r \
                --arg pid "$leave_peer_id" \
                '[(.result.remote_shards // [])[] | select(.peer_id == ($pid | tonumber))] | length')
              if [ "${remaining}" = "0" ]; then
                echo "all shards in collection ${col_name} moved off peer ${leave_peer_id} (verified from control)"
                break
              fi
              echo "waiting for ${remaining} shards in ${col_name} to finish transfer..."
            fi
            sleep 1
        done
    done
}

remove_peer() {
    echo "remove peer ${leave_peer_id} from cluster"
    # Use control endpoint — the leaving peer may be unreachable after shard migration.
    $CURL $CURL_TLS -sf -v -XDELETE ${control_uri}/cluster/peer/${leave_peer_id}
    if [ $? -ne 0 ]; then
      echo "ERROR: failed to remove peer ${leave_peer_id} from cluster"
      return 1
    fi
    echo "peer ${leave_peer_id} removed successfully"
}

leave_member() {
    echo "scaling in: move local shards and remove peer from cluster"
    echo "control endpoint: ${control_uri}"
    echo "leaving peer: ${KB_LEAVE_MEMBER_POD_NAME} (id=${leave_peer_id}, uri=${leave_peer_uri})"
    echo "leader peer id: ${leader_peer_id}"
    move_shards
    remove_peer
}

# lock file to prevent concurrent leave_member
# flock will return 1 if the lock is already held by another process, this is expected
(
  flock -n -x 9
  if [ $? != 0 ]; then
    echo "member is already in leaving"
    exit 1
  fi
  set -o errexit && leave_member
) 9>/var/lock/qdrant-leave-member-lock
