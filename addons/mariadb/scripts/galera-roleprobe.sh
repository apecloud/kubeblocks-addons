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
#   4 (Synced) -> "primary"   (writable, full Galera member)
#   anything else -> "secondary" (Joining/Donor/Joined — not writable)
#
# When the role file does not yet exist (early bootstrap, before mariadbd
# binds the local socket), publish "secondary" so KubeBlocks does not elect
# the node primary prematurely. The file appears within a few seconds after
# bootstrap completes.

set -eu

DATA_DIR="${DATA_DIR:-/var/lib/mysql}"
ROLE_FILE="${DATA_DIR}/.galera-role"

if [ -f "${ROLE_FILE}" ]; then
  role=$(cat "${ROLE_FILE}" 2>/dev/null || true)
  case "${role}" in
    primary|secondary)
      printf "%s" "${role}"
      exit 0
      ;;
  esac
fi

printf "secondary"
exit 0
