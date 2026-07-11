#!/bin/sh
# Probe Galera node role for KubeBlocks.
#
# Shebang is #!/bin/sh because kbagent (kubeblocks-tools image) only ships
# busybox sh; #!/bin/bash causes silent exit=1 with empty output. Script
# body must remain POSIX-compatible.
#
# IMPORTANT: kbagent has no mariadb client binary. KubeBlocks main API also
# dropped ExecAction.container, so even if cmpd-galera.yaml declares
# `roleProbe.exec.container: mariadb`, the action still runs inside kbagent.
# Therefore we cannot query mariadb from inside this script.
#
# Instead, the data plane (galera-start.sh background watcher inside the
# mariadb container) writes the current role to ${DATA_DIR}/.galera-role
# every few seconds based on wsrep_local_state. This script just reads it.
#
# Mapping from wsrep_local_state to KubeBlocks role:
#   4 + Primary component -> "primary" (writable, full Galera member)
#   anything else -> probe failure (Joining/Donor/Joined is not rollout-ready)
#
# Do not publish "secondary" for early bootstrap or SST/joiner states. For a
# Serial member update, KubeBlocks treats any role label as enough to continue
# the next pod. Publishing secondary before the node has rejoined can let a
# static-parameter restart take down multiple Galera members and lose quorum.

set -eu

DATA_DIR="${DATA_DIR:-/var/lib/mysql}"
ROLE_FILE="${DATA_DIR}/.galera-role"
# The watcher rewrites .galera-role every ~3s while the mariadb container is
# alive. If the mariadb container dies (crash-loop, OOM, node loss) the file
# stops being refreshed but survives on the PV, and kbagent — a separate
# container that stays up and runs this probe — would keep reading a stale
# "primary" and route writes to a dead node. Reject a role file that has not
# been refreshed within this staleness window (default 30s = 10 watcher ticks).
GALERA_ROLE_MAX_STALE_SECONDS="${GALERA_ROLE_MAX_STALE_SECONDS-30}"
# Validate the threshold up front. If it is empty / non-numeric / negative /
# zero, the later `[ "${age}" -gt "${threshold}" ]` test would error; inside an
# `if` that error does NOT trip `set -e`, so the script would fall through and
# publish "primary" — a fail-OPEN bypass of the freshness gate. Fail closed on
# a misconfigured threshold instead.
case "${GALERA_ROLE_MAX_STALE_SECONDS}" in
  ''|*[!0-9]*)
    echo "galera role probe misconfigured: GALERA_ROLE_MAX_STALE_SECONDS='${GALERA_ROLE_MAX_STALE_SECONDS}' must be a positive integer" >&2
    exit 1 ;;
esac
if [ "${GALERA_ROLE_MAX_STALE_SECONDS}" -lt 1 ]; then
  echo "galera role probe misconfigured: GALERA_ROLE_MAX_STALE_SECONDS='${GALERA_ROLE_MAX_STALE_SECONDS}' must be >= 1" >&2
  exit 1
fi

# Portable file-age in seconds (GNU/busybox `stat -c %Y`, BSD `stat -f %m`).
# Prints the age; returns non-zero if the mtime cannot be read.
_file_age_seconds() {
  _fas_now="$(date +%s 2>/dev/null)" || return 1
  _fas_mtime="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null)" || return 1
  [ -n "${_fas_mtime}" ] || return 1
  _fas_age=$(( _fas_now - _fas_mtime ))
  # A future mtime (clock skew / NTP step) yields a negative age. That is an
  # anomalous, not a fresh, state — a naive "age > threshold" test would pass
  # it and defeat the staleness gate. Clamp to a value that always reads stale.
  if [ "${_fas_age}" -lt 0 ]; then
    echo 2147483647
    return 0
  fi
  echo "${_fas_age}"
}

if [ -f "${ROLE_FILE}" ]; then
  age="$(_file_age_seconds "${ROLE_FILE}" || echo "")"
  if [ -z "${age}" ]; then
    echo "galera role not ready: cannot determine ${ROLE_FILE} freshness" >&2
    exit 1
  fi
  if [ "${age}" -gt "${GALERA_ROLE_MAX_STALE_SECONDS}" ]; then
    echo "galera role stale: ${ROLE_FILE} not refreshed for ${age}s (> ${GALERA_ROLE_MAX_STALE_SECONDS}s); writer likely dead" >&2
    exit 1
  fi
  role=$(cat "${ROLE_FILE}" 2>/dev/null || true)
  if [ "${role}" = "primary" ]; then
    printf "%s" "${role}"
    exit 0
  fi
  echo "galera role not rollout-ready: ${role:-empty}" >&2
  exit 1
fi

echo "galera role not ready: ${ROLE_FILE} missing" >&2
exit 1
