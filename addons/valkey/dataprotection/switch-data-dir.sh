#!/bin/bash
# switch-data-dir.sh — redis-aligned DP_RESTORE_KEY_PATTERNS support.
#
# When the Restore asks for only a subset of keys (DP_RESTORE_KEY_PATTERNS),
# the backup archive must NOT be extracted into the real DATA_DIR (the restored
# cluster must start empty and receive only the matching keys).  Instead the
# archive lands in ${DATA_DIR}/.restore_keys and the postReady restore-keys
# job starts a local Valkey on it and MIGRATEs the matching keys into the
# target.  This file is concatenated with restore.sh in the same `bash -c`,
# so the DATA_DIR reassignment below is what restore.sh sees.

if [ -n "$DP_RESTORE_KEY_PATTERNS" ]; then
    echo "DP_RESTORE_KEY_PATTERNS is set, switching data directory to ${DATA_DIR}/.restore_keys"
    DATA_DIR="${DATA_DIR}/.restore_keys"
fi
