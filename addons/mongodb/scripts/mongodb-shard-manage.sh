#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

readonly POLL_INTERVAL_SECONDS="${SYNCER_SHARD_POLL_INTERVAL_SECONDS:-2}"
readonly SYNCERCTL_BIN="${SYNCERCTL_BIN:-/tools/syncerctl}"

is_positive_integer() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_permanent_error() {
  local output=$1
  case "$output" in
    *"jumbo chunks"* | \
    *"no active destination shard is available"* | \
    *"already registered as shard"* | \
    *"belongs to replica set"* | \
    *"unknown state"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

poll_shard_operation() {
  local command=$1
  local timeout_seconds=$2
  local started_at=$SECONDS
  local output
  local status

  if ! is_positive_integer "$POLL_INTERVAL_SECONDS" || ! is_positive_integer "$timeout_seconds"; then
    echo "ERROR: shard operation poll interval and timeout must be positive integers" >&2
    return 1
  fi

  while true; do
    set +o errexit
    output=$("$SYNCERCTL_BIN" "$command" 2>&1)
    status=$?
    set -o errexit

    if [ -n "$output" ]; then
      printf '%s\n' "$output"
    fi
    if [ "$status" -eq 0 ]; then
      return 0
    fi
    if is_permanent_error "$output"; then
      echo "ERROR: $command failed permanently" >&2
      return "$status"
    fi
    if [ $((SECONDS - started_at)) -ge "$timeout_seconds" ]; then
      echo "ERROR: $command did not succeed within ${timeout_seconds}s" >&2
      return 1
    fi
    sleep "$POLL_INTERVAL_SECONDS"
  done
}

case "${1:-}" in
  add-shard)
    poll_shard_operation add-shard "${SYNCER_ADD_SHARD_TIMEOUT_SECONDS:-600}"
    ;;
  remove-shard)
    poll_shard_operation remove-shard "${SYNCER_REMOVE_SHARD_TIMEOUT_SECONDS:-3600}"
    ;;
  *)
    echo "Usage: $0 {add-shard|remove-shard}" >&2
    exit 2
    ;;
esac
