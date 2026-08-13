#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Source contract: a marker from the previous container lifetime cannot keep
# readiness green while restart bootstrap is running or after it fails.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRYPOINT="$ROOT/scripts/entrypoint.sh"

RESTART_BLOCK=$(awk '
  /if \[ -f "\$init_flag" \]; then/ { found=1 }
  found { print }
  found && /^else$/ { exit }
' "$ENTRYPOINT")

line_of() {
  local pattern=$1
  grep -nF -- "$pattern" <<< "$RESTART_BLOCK" | head -1 | cut -d: -f1
}

pass=0
fail=0
run_case() {
  local label=$1 function_name=$2
  if "$function_name"; then
    echo "PASS  $label"
    pass=$((pass + 1))
  else
    echo "FAIL  $label"
    fail=$((fail + 1))
  fi
}

case_old_marker_removed_before_restart_bootstrap() {
  local remove_line configure_line
  remove_line=$(line_of 'rm -f "$init_flag"')
  configure_line=$(line_of 'configure_function=configure_initialized')
  [ -n "$remove_line" ] && [ -n "$configure_line" ] &&
    [ "$remove_line" -lt "$configure_line" ]
}

case_success_is_the_only_marker_recreation_path() {
  grep -Fq -- 'mark_as_initialized' "$ENTRYPOINT" || return 1
  grep -Fq -- 'if wait_for_configure_process; then' "$ENTRYPOINT"
}

case_restart_block_has_no_unconditional_touch() {
  ! grep -Eq -- '(^|[[:space:];])touch[[:space:]]+.*init_flag' \
    <<< "$RESTART_BLOCK"
}

run_case "old marker is removed before restart bootstrap" \
  case_old_marker_removed_before_restart_bootstrap
run_case "only successful configure path can recreate the marker" \
  case_success_is_the_only_marker_recreation_path
run_case "restart branch has no unconditional marker touch" \
  case_restart_block_has_no_unconditional_touch

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
