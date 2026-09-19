#!/bin/sh
# Pure input handling shared by startup scripts. Never evaluate an environment value.
seaweedfs_fail() {
  printf 'SeaweedFS: %s\n' "$1" >&2
  exit 1
}

# The KubeBlocks componentVarRef contract supplies comma-separated actual FQDNs.
# Reject missing/duplicate entries; do not synthesize ordinals or a DNS suffix.
seaweedfs_endpoints() {
  [ -n "$1" ] || seaweedfs_fail 'required Pod FQDN list is empty'
  case "$1" in
    ,*|*,|*,,*|*[!a-zA-Z0-9.,-]*) seaweedfs_fail 'invalid Pod FQDN list' ;;
  esac
  seaweedfs_result=""
  seaweedfs_seen=","
  seaweedfs_old_ifs=$IFS
  IFS=,
  for seaweedfs_host in $1; do
    case "$seaweedfs_seen" in
      *",${seaweedfs_host},"*) seaweedfs_fail 'duplicate Pod FQDN' ;;
    esac
    seaweedfs_seen="${seaweedfs_seen}${seaweedfs_host},"
    seaweedfs_result="${seaweedfs_result}${seaweedfs_result:+,}${seaweedfs_host}:$2"
  done
  IFS=$seaweedfs_old_ifs
  printf '%s' "$seaweedfs_result"
}

seaweedfs_self() {
  [ -n "${POD_NAME:-}" ] || seaweedfs_fail 'POD_NAME is required'
  # Validate before splitting, including duplicate detection.
  seaweedfs_endpoints "${SEAWEEDFS_POD_FQDNS:-}" 1 >/dev/null
  seaweedfs_old_ifs=$IFS
  IFS=,
  for seaweedfs_host in $SEAWEEDFS_POD_FQDNS; do
    if [ "${seaweedfs_host%%.*}" = "$POD_NAME" ]; then
      IFS=$seaweedfs_old_ifs
      printf '%s' "$seaweedfs_host"
      return
    fi
  done
  IFS=$seaweedfs_old_ifs
  seaweedfs_fail 'current Pod is absent from the injected FQDN list'
}
