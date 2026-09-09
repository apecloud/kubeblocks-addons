#!/bin/bash
set -euo pipefail

if [[ -z "${KB_SWITCHOVER_CURRENT_NAME:-}" ]]; then
  echo "KB_SWITCHOVER_CURRENT_NAME is required" >&2
  exit 2
fi

args=(switchover --primary "$KB_SWITCHOVER_CURRENT_NAME")
if [[ -n "${KB_SWITCHOVER_CANDIDATE_NAME:-}" ]]; then
  args+=(--candidate "$KB_SWITCHOVER_CANDIDATE_NAME")
fi

# Bound request submission below the action cap; Syncer owns HA convergence.
if timeout -k 5 50 /tools/syncerctl "${args[@]}"; then
  exit 0
else
  status=$?
  if [[ "$status" == 124 || "$status" == 137 ]]; then
    echo "Syncer switchover request timed out; check DCS and roles before retrying, as the request may already be accepted" >&2
  fi
  exit "$status"
fi
