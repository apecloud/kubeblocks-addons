# shellcheck shell=sh
#
# Shared helpers for Qdrant lifecycle scripts (setup, member-leave, etc.).
# Functions derive pod/network identity from KubeBlocks env vars and wrap
# authenticated HTTP calls to the Qdrant REST API.

# Read a required environment variable by name.
# Args: $1 - variable name (e.g. CURRENT_POD_NAME)
# Prints the value on success; writes an error to stderr and returns 1 if unset.
qdrant_required_env() {
  qdrant_required_var_name="$1"
  eval "qdrant_required_var_value=\${${qdrant_required_var_name}:-}"
  if [ -z "$qdrant_required_var_value" ]; then
    echo "ERROR: Required environment variable ${qdrant_required_var_name} is not set." >&2
    return 1
  fi
  printf "%s" "$qdrant_required_var_value"
}

# Extract the ordinal (trailing numeric suffix) from a pod name.
# Args: $1 - pod name (defaults to CURRENT_POD_NAME)
# Prints the ordinal (e.g. "0" from "my-qdrant-0"); returns 1 if missing or non-numeric.
qdrant_pod_ordinal() {
  qdrant_ordinal_pod_name="${1:-${CURRENT_POD_NAME:-}}"
  if [ -z "$qdrant_ordinal_pod_name" ]; then
    echo "ERROR: pod name is empty." >&2
    return 1
  fi

  qdrant_ordinal="${qdrant_ordinal_pod_name##*-}"
  case "$qdrant_ordinal" in
    ""|*[!0-9]*)
      echo "ERROR: pod name ${qdrant_ordinal_pod_name} does not end with a numeric ordinal." >&2
      return 1
      ;;
  esac
  printf "%s" "$qdrant_ordinal"
}

# Resolve this pod's Kubernetes FQDN from the runtime hostname.
qdrant_runtime_pod_fqdn() {
  hostname -f
}

# Return this pod's FQDN for Qdrant's advertised peer URI.
qdrant_current_pod_fqdn() {
  qdrant_current_fqdn="$(qdrant_runtime_pod_fqdn)" || {
    echo "ERROR: failed to resolve current pod FQDN with hostname -f." >&2
    return 1
  }
  if [ -z "$qdrant_current_fqdn" ]; then
    echo "ERROR: hostname -f returned an empty current pod FQDN." >&2
    return 1
  fi
  printf "%s" "$qdrant_current_fqdn"
}

# Return the ComponentService host used to discover or join the cluster.
qdrant_bootstrap_service_host() {
  qdrant_required_env QDRANT_COMPONENT_SERVICE_HOST
}

# Return whether this pod should bootstrap a new cluster (ordinal 0 with no peers).
# Args: $1 - pod name (defaults to CURRENT_POD_NAME)
# Returns 0 if ordinal is 0, 1 otherwise.
qdrant_should_self_bootstrap() {
  qdrant_self_ordinal="$(qdrant_pod_ordinal "${1:-${CURRENT_POD_NAME:-}}")" || return 1
  [ "$qdrant_self_ordinal" = "0" ]
}

# Read service.api_key from the on-disk Qdrant config file.
# Uses QDRANT_CONFIG_FILE when set (default: /qdrant/config/config.yaml).
# Prints the key when found; prints nothing and returns 0 if the file is unreadable
# or no api_key is configured.
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

# Resolve the API key used for authenticated Qdrant HTTP requests.
# Prefers QDRANT__SERVICE__API_KEY; falls back to qdrant_config_service_api_key.
# Prints the key, or nothing when auth is disabled.
qdrant_effective_api_key() {
  if [ -n "${QDRANT__SERVICE__API_KEY:-}" ]; then
    printf "%s" "$QDRANT__SERVICE__API_KEY"
    return
  fi
  qdrant_config_service_api_key
}

# Run curl against the Qdrant API, attaching the api-key header when configured.
# Temporarily disables xtrace while the command runs so the key is not logged.
# Args: passed through to curl (URL, -sf, --max-time, etc.)
# Uses QDRANT_CURL_BIN (default: curl) and honors CURL_TLS for TLS options.
# Returns the curl exit code.
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
