#!/usr/bin/env bash

set -euo pipefail

scheme=http
tls_args=""
if [ "${TLS_ENABLED:-}" = "true" ]; then
  scheme=https
  tls_args="-k"
fi

export CURL_TLS="$tls_args"
export QDRANT_CURL_BIN=/qdrant/tools/curl

# shellcheck disable=SC1091
. /qdrant/scripts/common.sh

qdrant_curl -sf "${scheme}://localhost:6333/" >/dev/null
