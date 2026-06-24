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

if [ -f "${ROLE_FILE}" ]; then
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
