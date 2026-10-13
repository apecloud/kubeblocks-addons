#!/usr/bin/env bash

set -eo pipefail

common_library_file="/qdrant/scripts/common.sh"
# shellcheck disable=SC1090
source "${common_library_file}"

qdrant_set_tls_variables

role=$(qdrant_curl -sS -f "$SCHEME://localhost:6333/cluster" | jq -r '.result.raft_info.role')
if [[ "$role" = "Leader" ]]; then
  echo -n "leader"
elif [[ "$role" = "Follower" ]]; then
  echo -n "follower"
elif [[ -z "$role" ]]; then
  echo -n "unknown"
else
  echo -n "$role"
fi
