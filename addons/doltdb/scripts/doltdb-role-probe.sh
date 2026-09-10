#!/bin/sh
set -eu

err_file="${TMPDIR:-/tmp}/doltdb-role-probe.$$"
trap 'rm -f "$err_file"' EXIT

set +e
result="$(DOLT_NO_DATABASE=true /scripts/doltdb-sql.sh "SELECT @@GLOBAL.dolt_cluster_role, @@GLOBAL.dolt_cluster_role_epoch;" 2>"$err_file")"
status=$?
set -e

if [ "$status" -ne 0 ]; then
  cat "$err_file" >&2 || true
  exit "$status"
fi

line="$(printf '%s\n' "$result" | tail -n 1 | tr -d '\r')"
role="$(printf '%s\n' "$line" | cut -d, -f1 | tr -d '"' | tr -d '[:space:]')"
epoch="$(printf '%s\n' "$line" | cut -d, -f2 | tr -d '"' | tr -d '[:space:]')"

case "$role" in
  primary|standby)
    ;;
  detected_broken_config)
    echo "dolt cluster role is detected_broken_config at epoch ${epoch}; refusing to publish a KubeBlocks role" >&2
    exit 1
    ;;
  *)
    echo "unexpected dolt cluster role probe output: ${line}" >&2
    exit 1
    ;;
esac

case "$epoch" in
  ''|*[!0-9]*)
    echo "unexpected dolt cluster role epoch in probe output: ${line}" >&2
    exit 1
    ;;
esac

printf '%s %s\n' "$role" "$epoch"
