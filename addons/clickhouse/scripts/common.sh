#!/bin/bash
export RETRY_ATTEMPTS=3
export SLEEP_INTERVAL=5
export TLS_MOUNT_PATH="/etc/pki/tls"
export CLICKHOUSE_PORT="${CLICKHOUSE_TCP_PORT:-9000}"
export CLICKHOUSE_HOST="${CLICKHOUSE_HOST:-localhost}"
export CLICKHOUSE_KEEPER_PORT="${CLICKHOUSE_KEEPER_TCP_PORT:-9181}"
if [[ "${TLS_ENABLED:-false}" == "true" ]]; then
	export CLICKHOUSE_PORT="${CLICKHOUSE_TCP_SECURE_PORT:-9440}"
	export CLICKHOUSE_KEEPER_PORT="${CLICKHOUSE_KEEPER_TCP_TLS_PORT:-9281}"
	export CLICKHOUSE_TLS_CA="${TLS_MOUNT_PATH}/ca.pem"
	export CLICKHOUSE_TLS_CERT="${TLS_MOUNT_PATH}/cert.pem"
	export CLICKHOUSE_TLS_KEY="${TLS_MOUNT_PATH}/key.pem"
fi

function ch_query() {
	local host="$1"
	local query="$2"
	local ch_args=(--user "${CLICKHOUSE_ADMIN_USER}" --password "${CLICKHOUSE_ADMIN_PASSWORD}" --host "${host}" --port "$CLICKHOUSE_PORT" --connect_timeout=5)
	clickhouse-client "${ch_args[@]}" --query "$query"
}

# Low-level keeper client execution with connection retry
# Handles connection issues, timeouts, and transient network problems
function keeper_run() {
	local host="$1"
	local query="$2"

	[[ -z "$host" || -z "$query" ]] && {
		echo "ERROR: keeper_run requires host and query parameters" >&2
		return 1
	}

	for attempt in $(seq 1 $RETRY_ATTEMPTS); do
		local output
		local keeper_args=(
			--connection-timeout=15
			--session-timeout=30
			--operation-timeout=15
			--history-file=/dev/null
			-h "$host"
			-p "$CLICKHOUSE_KEEPER_PORT"
			--query "$query"
		)
		if [[ "${TLS_ENABLED:-false}" == "true" ]]; then
			keeper_args+=(--secure --tls-ca-file "$CLICKHOUSE_TLS_CA" --tls-cert-file "$CLICKHOUSE_TLS_CERT" --tls-key-file "$CLICKHOUSE_TLS_KEY")
		fi
		if output=$(clickhouse-keeper-client "${keeper_args[@]}" 2>&1); then

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

	# Use TLS port if TLS is enabled
	if [[ "$TLS_ENABLED" == "true" ]]; then
		# For TLS connections, use openssl s_client for 4LW commands
		local mode
		mode=$(printf "srvr\n" | timeout 2 openssl s_client \
			-connect "$host:$CLICKHOUSE_KEEPER_PORT" \
			-CAfile "$CLICKHOUSE_TLS_CA" \
			-cert "$CLICKHOUSE_TLS_CERT" \
			-key "$CLICKHOUSE_TLS_KEY" \
			-quiet \
			-ign_eof 2>/dev/null | grep Mode)
		echo "$mode" | awk '{print $2}'
	else
		local mode
		mode=$(echo srvr | /shared-tools/nc -w 1 "$host" "$CLICKHOUSE_KEEPER_PORT" | grep Mode)
		echo "$mode" | awk '{print $2}'
	fi
}

# Get keeper node mode by keeper
function get_mode_by_keeper() {
	local mode=$(keeper_run "$1" "srvr" | grep Mode)
	echo "$mode" | awk '{print $2}'
}

# Find leader node from member addresses
function find_leader() {
	local member_addresses="$1"
	[[ -z "$member_addresses" ]] && return 1

	while IFS=',' read -ra members; do
		for member_addr in "${members[@]}"; do
			local member_fqdn="${member_addr%:*}"
			mode=$(get_mode "$member_fqdn")
			if [[ "$mode" == "leader" || "$mode" == "standalone" ]]; then
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
