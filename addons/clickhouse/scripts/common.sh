# Constants for retry logic
readonly RETRY_ATTEMPTS=6
readonly SLEEP_INTERVAL=10

# Low-level keeper client execution with connection retry
# Handles connection issues, timeouts, and transient network problems
function keeper_run() {
  local host="$1"
  local query="$2"
  local port="${CLICKHOUSE_KEEPER_TCP_PORT:-9181}"

  [[ -z "$host" || -z "$query" ]] && {
    echo "ERROR: keeper_run requires host and query parameters" >&2
    return 1
  }

  for attempt in $(seq 1 $RETRY_ATTEMPTS); do
    local output
    if output=$(clickhouse-keeper-client \
      --connection-timeout=15 \
      --session-timeout=30 \
      --operation-timeout=15 \
      --history-file=/dev/null \
      -h "$host" \
      -p "$port" \
      --query "$query" 2>&1); then

      if [[ "$output" != *"Coordination error"* ]] &&
        [[ "$output" != *"Connection refused"* ]] &&
        [[ "$output" != *"Timeout"* ]]; then
        echo "$output"
        return 0
      fi
      echo "WARN: Command executed but returned error: $output" >&2
    else
      echo "WARN: Command failed to execute on attempt $attempt" >&2
    fi

    if [[ $attempt -eq $RETRY_ATTEMPTS ]]; then
      echo "ERROR: Failed to execute '$query' on $host after $RETRY_ATTEMPTS attempts" >&2
      return 1
    fi

    sleep $((attempt * $SLEEP_INTERVAL))
  done
}

# Retry keeper operation with verification
function retry_keeper_operation() {
  local keeper_cmd="$1"
  local verify_cmd="$2"

  [[ -z "$keeper_cmd" || -z "$verify_cmd" ]] && {
    echo "ERROR: retry_keeper_operation requires keeper_cmd and verify_cmd" >&2
    return 1
  }

  for attempt in $(seq 1 $RETRY_ATTEMPTS); do
    if eval "$keeper_cmd"; then
      sleep $SLEEP_INTERVAL
      if eval "$verify_cmd"; then
        return 0
      fi
    fi

    if [[ $attempt -eq $RETRY_ATTEMPTS ]]; then
      echo "ERROR: Operation failed after $RETRY_ATTEMPTS attempts" >&2
      return 1
    fi

    sleep $SLEEP_INTERVAL
  done
}

# Get keeper cluster configuration
function get_config() {
  local host="$1"
  [[ -z "$host" ]] && return 1
  keeper_run "$host" "get '/keeper/config'"
}

# Get keeper node mode (leader/follower/observer)
function get_mode() {
  local host="$1"
  local mode=$(echo srvr | /shared-tools/nc "$host" 9181 | grep Mode)
  echo "$mode" | awk '{print $2}'
}

# Get keeper node mode by keeper
function get_mode_by_keeper() {
  local mode=$(keeper_run "$1" "srvr" | grep Mode)
  echo "$mode" | awk '{print $2}'
}

# Find leader node from member addresses
function find_leader() {
  local member_addresses="$1"
  local exclude_member="${2:-}"
  [[ -z "$member_addresses" ]] && return 1

  while IFS=',' read -ra members; do
    for member_addr in "${members[@]}"; do
      local member_fqdn="${member_addr%:*}"
      [[ -n "$exclude_member" && "$member_fqdn" == *"$exclude_member"* ]] && continue
      if [[ "$(get_mode "$member_fqdn")" == "leader" ]]; then
        echo "$member_fqdn"
        return 0
      fi
    done
  done <<<"$member_addresses"

  return 1
}

# Extract ordinal number from pod name
function extract_ordinal_from_pod_name() {
  local pod_name="$1"
  [[ -z "$pod_name" ]] && return 1
  echo "${pod_name##*-}"
}
