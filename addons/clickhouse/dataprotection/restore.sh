#!/bin/bash
set -eo pipefail

# Supports: standalone (single node) and cluster (multi-shard) topologies
# Strategy: first shard restores schema with ON CLUSTER, others wait for sync

trap handle_exit EXIT
generate_backup_config
set_clickhouse_backup_config_env

# 1. Detect topology mode: standalone or cluster
mode_info=$(detect_restore_mode) || exit 1

# 2. Restore schema + data + marker
do_restore "${DP_BACKUP_NAME}" "$mode_info" || exit 1

# 3. Cleanup local backups
delete_backups_except ""
