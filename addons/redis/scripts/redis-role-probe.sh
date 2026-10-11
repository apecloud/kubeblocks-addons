#!/bin/bash
set -euo pipefail

if (( $# > 1 )); then
  echo "usage: $0 [dbctl-path]" >&2
  exit 2
fi

dbctl_bin="${1:-/tools/dbctl}"
role_output="$("${dbctl_bin}" redis getrole)"
role_output="${role_output//$'\r'/}"
role_output="${role_output//$'\n'/ }"
read -r role extra <<<"${role_output}"

if [[ -z "${role:-}" || -n "${extra:-}" ]]; then
  echo "unexpected Redis role output" >&2
  exit 1
fi

case "${role}" in
  primary|secondary)
    printf '%s\n' "${role}"
    exit 0
    ;;
  *)
    echo "unexpected Redis role output" >&2
    exit 1
    ;;
esac
