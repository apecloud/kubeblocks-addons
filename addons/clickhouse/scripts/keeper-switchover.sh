#!/bin/bash
set -euxo pipefail

leader_fqdn="$KB_SWITCHOVER_CURRENT_FQDN"
candidate_fqdn="${KB_SWITCHOVER_CANDIDATE_FQDN:-}"

function keeper_run() {
  local host="$1"
  local query="$2"
  local attempt=1
  local max_retries=4
  local retry_interval=5

  while [[ $attempt -le $max_retries ]]; do
    if output=$(clickhouse-keeper-client --connection-timeout=10 --session-timeout=10 --operation-timeout=10 --history-file=/dev/null -h "$host" --query "$query" 2>&1); then
      if [[ "$output" != *"Coordination error"* ]]; then
        echo "$output"
        return 0
      fi
    fi
    if [[ $attempt -eq $max_retries ]]; then
      echo "ERROR: Failed to execute command '$query' on $host after $max_retries attempts"
      exit 1
    fi
    sleep $retry_interval
    attempt=$((attempt + 1))
  done
}

function get_config() {
 keeper_run "$1" "get '/keeper/config'"
}

function get_mode() {
  local mode=$(keeper_run "$1" "srvr" | grep Mode)
  echo "$mode" | awk '{print $2}'
}

if [ "$KB_SWITCHOVER_ROLE" != "leader" ]; then
    echo "switchover not triggered for primary, nothing to do, exit 0."
    exit 0
fi

# 1. Get current config
config=$(get_config "$leader_fqdn")

# 2. Find candidate
if [[ -z "$candidate_fqdn" ]]; then
  candidate_fqdn=$(echo "$config" | grep 'participant' | grep -v "$leader_fqdn" | \
  head -n 1 | cut -d'=' -f2 | cut -d':' -f1)
else
  echo "$config" | grep -qE "^server\.[0-9]+=$candidate_fqdn" || {
    echo "ERROR: Specified candidate '$candidate_fqdn' not found in config."
    exit 1
  }
fi

if [[ -z "$candidate_fqdn" ]]; then
  echo "ERROR: Could not find a candidate follower."
  exit 1
fi

# 3. Change the priority of the candidate to 8, and the others to 1
pre_leader=$(echo "$config" | grep "$leader_fqdn")
pre_leader=${pre_leader%;*}";1"
pre_leader_id=$(echo "$pre_leader" | cut -d'=' -f1 | cut -d'.' -f2)
# server.1=ch-cluster-ch-keeper-0.ch-cluster-ch-keeper-headless.default.svc.cluster.local:9234;participant;1
while IFS= read -r line; do
  if [[ "$line" == server.*";participant;"* ]]; then
    line_fqdn=$(echo "$line" | cut -d'=' -f2 | cut -d':' -f1)
    original_priority="${line##*;}"
    base_config="${line%;*}"
    if echo "$line_fqdn" | grep -q "$candidate_fqdn"; then
      if [[ "$original_priority" -ne 8 ]]; then
        echo "INFO: Changing priority of candidate $candidate_fqdn from $original_priority to 8"
        new_priority=8
      fi
    elif [[ "$original_priority" -ne 1 ]]; then
      new_priority=1
    else
      continue
    fi
    # change priority need to send request to leader
    keeper_run "$leader_fqdn" "reconfig add '$base_config;$new_priority'"
  fi
done <<< "$config"

# 4. remove the leader from the config
keeper_run "$leader_fqdn" "reconfig remove '$pre_leader_id'"

# 5. Check if candidate becomes leader
attempt=1
max_wait_attempts=20
wait_interval_seconds=5
while [[ $attempt -le $max_wait_attempts ]]; do
  mode=$(get_mode "$candidate_fqdn")
  if [[ "$mode" == "leader" ]]; then
    break
  else
    echo "INFO: Candidate $candidate_fqdn is not leader after $attempt query, current mode: $mode"
  fi
  sleep "$wait_interval_seconds"
  attempt=$((attempt + 1))
done

if [[ "$mode" != "leader" ]]; then
  keeper_run "$leader_fqdn" "reconfig add '$pre_leader'"
  echo "ERROR: Candidate $candidate_fqdn did not become leader after $max_wait_attempts tries."
  exit 1
fi

# 6. Re-add after pre leader reboot
keeper_run "$candidate_fqdn" "reconfig add '$pre_leader'"