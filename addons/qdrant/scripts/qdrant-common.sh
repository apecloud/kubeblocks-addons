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

# Derive the component pod name prefix by stripping the ordinal suffix.
# Args: $1 - pod name (defaults to CURRENT_POD_NAME)
# Prints the prefix (e.g. "my-qdrant" from "my-qdrant-0"); returns 1 on failure.
qdrant_pod_prefix() {
  qdrant_prefix_pod_name="${1:-${CURRENT_POD_NAME:-}}"
  qdrant_prefix_ordinal="$(qdrant_pod_ordinal "$qdrant_prefix_pod_name")" || return 1
  qdrant_prefix="${qdrant_prefix_pod_name%-${qdrant_prefix_ordinal}}"
  if [ -z "$qdrant_prefix" ] || [ "$qdrant_prefix" = "$qdrant_prefix_pod_name" ]; then
    echo "ERROR: failed to derive component pod prefix from pod ${qdrant_prefix_pod_name}." >&2
    return 1
  fi
  printf "%s" "$qdrant_prefix"
}

# Resolve the Kubernetes cluster DNS domain.
# Uses CLUSTER_DOMAIN when set, otherwise "cluster.local"; strips leading/trailing dots.
# Prints the normalized domain; returns 1 if the result is empty.
qdrant_cluster_domain() {
  qdrant_domain="${CLUSTER_DOMAIN:-cluster.local}"
  qdrant_domain="${qdrant_domain#.}"
  qdrant_domain="${qdrant_domain%.}"
  if [ -z "$qdrant_domain" ]; then
    echo "ERROR: CLUSTER_DOMAIN resolved to an empty value." >&2
    return 1
  fi
  printf "%s" "$qdrant_domain"
}

# Build the headless-service FQDN for a Qdrant pod.
# Args: $1 - pod name (defaults to CURRENT_POD_NAME)
# Prints: <pod>.<prefix>-headless.<namespace>.svc.<domain>
qdrant_current_pod_fqdn() {
  qdrant_current_pod_name="${1:-$(qdrant_required_env CURRENT_POD_NAME)}" || return 1
  qdrant_current_prefix="$(qdrant_pod_prefix "$qdrant_current_pod_name")" || return 1
  qdrant_current_namespace="$(qdrant_required_env KB_NAMESPACE)" || return 1
  qdrant_current_domain="$(qdrant_cluster_domain)" || return 1
  printf "%s.%s-headless.%s.svc.%s" \
    "$qdrant_current_pod_name" \
    "$qdrant_current_prefix" \
    "$qdrant_current_namespace" \
    "$qdrant_current_domain"
}

# Build the cluster Service host used to reach the bootstrap (ordinal-0) node.
# Args: $1 - pod name used only to derive the component prefix (defaults to CURRENT_POD_NAME)
# Prints: <prefix>-qdrant.<namespace>.svc.<domain>
qdrant_bootstrap_service_host() {
  qdrant_cluster_component_name="$(qdrant_required_env CLUSTER_COMPONENT_NAME)" || return 1
  qdrant_service_name="$(qdrant_required_env QDRANT_SERVICE_NAME)" || return 1
  qdrant_bootstrap_namespace="$(qdrant_required_env KB_NAMESPACE)" || return 1
  qdrant_bootstrap_domain="$(qdrant_cluster_domain)" || return 1
  printf "%s-%s.%s.svc.%s" \
    "$qdrant_cluster_component_name" \
    "$qdrant_service_name" \
    "$qdrant_bootstrap_namespace" \
    "$qdrant_bootstrap_domain"
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
