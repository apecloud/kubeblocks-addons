#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

set -euo pipefail

ADDON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0
fail=0

check() {
  local label="$1"
  shift
  if "$@"; then
    echo "PASS  $label"
    pass=$((pass + 1))
  else
    echo "FAIL  $label"
    fail=$((fail + 1))
  fi
}

no_remove_ag_reference() {
  ! grep -R -E -n \
    --exclude='remove_ag_ops_absence_test.sh' \
    --exclude='remove_ag_upgrade_migration.yaml' \
    --exclude='remove_ag_upgrade_migration.sh' \
    '(mssql-dynamic-remove-ag|reomve-ag|name:[[:space:]]+remove-ag|ops_remove_ag\.sh|DROP[[:space:]]+AVAILABILITY[[:space:]]+GROUP|ag is already removed)' \
    "$ADDON_DIR/templates" "$ADDON_DIR/scripts"
}

check "remove-ag OpsDefinition template is absent" \
  test ! -e "$ADDON_DIR/templates/ops/dynamic_remove_ag.yaml"
check "remove-ag action script is absent" \
  test ! -e "$ADDON_DIR/scripts/ops_remove_ag.sh"
check "production templates and scripts expose no remove-ag action" \
  no_remove_ag_reference
check "cluster bootstrap still creates its single availability group" \
  grep -Fq "CREATE AVAILABILITY GROUP [\$DEFAULT_AG_NAME]" "$ADDON_DIR/scripts/entrypoint.sh"
check "switchover still targets the cluster availability group" \
  grep -Fq 'DEFAULT_AG_NAME' "$ADDON_DIR/scripts/switchover.sh"

echo
echo "Total: ${pass} passed, ${fail} failed"
test "$fail" -eq 0
