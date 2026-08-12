#!/bin/bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

if [ "$IS_REMOTE_STANDBY" == "true" ]; then
  printf "primary"
  exit 0
fi

# Query the syncer DCS for authoritative role instead of AG DMV.
# The AG DMV (sys.dm_hadr_availability_replica_states) can return stale PRIMARY
# for a brief window after pod restart, causing dual-primary role label flaps.
# The syncer DCS is the single source of truth for role after leader election.
# Bound the call so it returns before kbagent's probe timeoutSeconds (4s) fires;
# capture stderr so syncerctl's own errors show up in the probe diagnostics.
role=$(timeout 3s /tools/syncerctl getrole 2>&1)
rc=$?
role=$(echo "$role" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

if [ "$rc" -eq 0 ] && [[ "$role" =~ ^(primary|secondary)$ ]]; then
  printf "%s" "$role"
else
  # Fail the probe (non-zero) so the controller keeps the last trusted role label
  # instead of treating an indeterminate role as a successful empty sample.
  # A timeout (rc=124) takes this branch too.
  echo "invalid role from syncerctl: $role" >&2
  exit 1
fi
exit 0
