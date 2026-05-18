#!/bin/bash
set -euo pipefail

role="$(/tools/dbctl redis getrole | tr -d '[:space:]')"
case "${role}" in
  primary|secondary)
    ;;
  *)
    echo "${role}"
    exit 0
    ;;
esac

role_snapshot_period_seconds="${ROLE_SNAPSHOT_PERIOD_SECONDS:-15}"
now_us="$(date +%s%6N)"
period_us="$((role_snapshot_period_seconds * 1000000))"
term="$((now_us / period_us * period_us))"
pod_name="${CURRENT_POD_NAME:-}"
pod_uid="${CURRENT_POD_UID:-}"

if [ -z "${pod_name}" ]; then
  echo "${role}"
  exit 0
fi

printf '{"term":"%s","PodRoleNamePairs":[{"podName":"%s","roleName":"%s","podUid":"%s"}]}\n' \
  "${term}" "${pod_name}" "${role}" "${pod_uid}"
