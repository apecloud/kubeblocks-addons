#!/bin/sh
set -eu

# KubeBlocks invokes this on the current primary only. We demote this instance
# then promote the candidate using the same configuration epoch (current + 1).

if [ "${KB_SWITCHOVER_ROLE:-}" != "primary" ]; then
  echo "switchover not triggered for primary, nothing to do, exit 0."
  exit 0
fi

if [ -z "${KB_SWITCHOVER_CANDIDATE_FQDN:-}" ] && [ -z "${KB_SWITCHOVER_CANDIDATE_NAME:-}" ]; then
  echo "KB_SWITCHOVER_CANDIDATE_FQDN or KB_SWITCHOVER_CANDIDATE_NAME is required for Dolt switchover" >&2
  exit 1
fi

CANDIDATE_HOST="${KB_SWITCHOVER_CANDIDATE_FQDN:-${KB_SWITCHOVER_CANDIDATE_NAME}}"

dolt_local_q() {
  dolt --host 127.0.0.1 --port 3306 --no-tls sql -q "$1"
}

extract_scalar() {
  _hdr=$1
  _out=$2
  printf '%s\n' "$_out" | awk -v hdr="$_hdr" '/^\|/{
    gsub(/^[ \t]*\|[ \t]*/, "");
    gsub(/[ \t]*\|[ \t]*$/, "");
    if ($1 != hdr && $1 != "") { print $1; exit }
  }'
}

epoch_out=$(dolt_local_q "select @@GLOBAL.dolt_cluster_role_epoch;" 2>/dev/null || true)
current_epoch=$(extract_scalar '@@GLOBAL.dolt_cluster_role_epoch' "$epoch_out")

case "$current_epoch" in
  '' | *[!0-9]*)
    echo "Could not read @@GLOBAL.dolt_cluster_role_epoch from local instance" >&2
    exit 1
    ;;
esac

new_epoch=$((current_epoch + 1))

role_out=$(dolt_local_q "select @@GLOBAL.dolt_cluster_role;" 2>/dev/null || true)
current_role=$(extract_scalar '@@GLOBAL.dolt_cluster_role' "$role_out")

if [ "$current_role" != "primary" ]; then
  echo "Local instance role is '${current_role}', expected primary; aborting" >&2
  exit 1
fi

echo "Demoting local primary to standby with epoch ${new_epoch}"
dolt_local_q "CALL dolt_assume_cluster_role('standby', ${new_epoch});"

echo "Promoting candidate ${CANDIDATE_HOST} to primary with epoch ${new_epoch}"
dolt --host "$CANDIDATE_HOST" --port 3306 --no-tls sql -q \
  "CALL dolt_assume_cluster_role('primary', ${new_epoch});"

echo "Dolt switchover completed."
