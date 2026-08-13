#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Source contract: readiness cannot stay green during failed restart bootstrap,
# and a failure must retain enough identity to retry the restart path.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRYPOINT="$ROOT/scripts/entrypoint.sh"

RESTART_BLOCK=$(awk '
  /if \[ -f "\$init_flag" \] \|\| \[ -f "\$restart_configure_flag" \]; then/ { found=1 }
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
  local retry_line remove_line configure_line
  retry_line=$(line_of 'touch "$restart_configure_flag"')
  remove_line=$(line_of 'rm -f "$init_flag"')
  configure_line=$(line_of 'configure_function=configure_initialized')
  [ -n "$retry_line" ] && [ -n "$remove_line" ] && [ -n "$configure_line" ] &&
    [ "$retry_line" -lt "$remove_line" ] &&
    [ "$remove_line" -lt "$configure_line" ]
}

case_failure_retries_restart_path() {
  grep -Fq -- 'if [ -f "$init_flag" ] || [ -f "$restart_configure_flag" ]; then' \
    "$ENTRYPOINT"
}

case_success_restores_readiness_and_clears_retry_identity() {
  local mark_block
  mark_block=$(awk '/^function mark_as_initialized\(\)/,/^}/' "$ENTRYPOINT")
  grep -Fq -- 'touch "$init_flag"' <<< "$mark_block" || return 1
  grep -Fq -- 'rm -f "$restart_configure_flag"' <<< "$mark_block"
}

case_restart_block_has_no_unconditional_touch() {
  ! grep -Eq -- '(^|[[:space:];])touch[[:space:]]+.*init_flag' \
    <<< "$RESTART_BLOCK"
}

run_case "old marker is removed before restart bootstrap" \
  case_old_marker_removed_before_restart_bootstrap
run_case "failed bootstrap retains restart-path identity" \
  case_failure_retries_restart_path
run_case "success restores readiness and clears retry identity" \
  case_success_restores_readiness_and_clears_retry_identity
run_case "restart branch has no unconditional marker touch" \
  case_restart_block_has_no_unconditional_touch

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
