# shellcheck shell=sh

qdrant_config_service_api_key() {
  config_file="${QDRANT_CONFIG_FILE:-/qdrant/config/config.yaml}"
  [ -r "$config_file" ] || return 0

  awk '
    /^[[:space:]]*#/ { next }
    /^[^[:space:]][^:]*:/ {
      section = $1
      sub(/:.*/, "", section)
      next
    }
    section == "service" {
      line = $0
      sub(/[[:space:]]+#.*/, "", line)
      if (line ~ /^[[:space:]]*api_key[[:space:]]*:/) {
        sub(/^[[:space:]]*api_key[[:space:]]*:[[:space:]]*/, "", line)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        gsub(/^["'\''"]|["'\''"]$/, "", line)
        if (line != "" && line != "null") {
          print line
          exit
        }
      }
    }
  ' "$config_file"
}

qdrant_effective_api_key() {
  if [ -n "${QDRANT__SERVICE__API_KEY:-}" ]; then
    printf "%s" "$QDRANT__SERVICE__API_KEY"
    return
  fi
  qdrant_config_service_api_key
}

qdrant_curl() {
  qdrant_xtrace_enabled=0
  case "$-" in
    *x*)
      qdrant_xtrace_enabled=1
      set +x
      ;;
  esac

  api_key="$(qdrant_effective_api_key)"
  if [ -n "$api_key" ]; then
    "${QDRANT_CURL_BIN:-curl}" ${CURL_TLS:-} -H "api-key: ${api_key}" "$@"
  else
    "${QDRANT_CURL_BIN:-curl}" ${CURL_TLS:-} "$@"
  fi
  qdrant_curl_rc=$?

  if [ "$qdrant_xtrace_enabled" = "1" ]; then
    set -x
  fi

  return "$qdrant_curl_rc"
}
