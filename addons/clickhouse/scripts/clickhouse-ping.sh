#!/bin/bash
set -euo pipefail

PORT="${CLICKHOUSE_HTTP_PORT:-8123}"
CURL_ARGS=(
	-sf
	--max-time 3
	"http://127.0.0.1:${PORT}/ping"
)

if [[ "${TLS_ENABLED:-false}" == "true" ]]; then
	PORT="${CLICKHOUSE_HTTPS_PORT:-8443}"
	CURL_ARGS=(
		-sf
		--max-time 3
		--cacert /etc/pki/tls/ca.pem
		--cert /etc/pki/tls/cert.pem
		--key /etc/pki/tls/key.pem
		"https://127.0.0.1:${PORT}/ping"
	)
fi

if ! /shared-tools/curl "${CURL_ARGS[@]}" >/dev/null; then
	echo "Readiness probe failed" >&2
	exit 1
fi
