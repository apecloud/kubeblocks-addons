#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp -R "$ROOT/addons/mssql" "$TMP/mssql"
cp -R "$ROOT/addons/kblib" "$TMP/kblib"

helm dependency build "$TMP/mssql" >/dev/null
helm template mssql "$TMP/mssql" \
  --namespace kb-system \
  --show-only templates/cmpd.yaml >"$TMP/cmpd.yaml"

awk '
  /^[[:space:]]+reconfigure:$/ {
    reconfigure_count++
    in_reconfigure = 1
    next
  }
  in_reconfigure && /^[[:space:]]+timeoutSeconds: 60$/ {
    timeout_count++
    next
  }
  in_reconfigure && /^[[:space:]]+exec:$/ {
    exec_count++
    in_reconfigure = 0
    next
  }
  in_reconfigure && /^[[:space:]]+[[:alnum:]_-]+:/ {
    missing_timeout = 1
    in_reconfigure = 0
  }
  END {
    if (reconfigure_count == 0) {
      print "FAIL  rendered manifest has no reconfigure action" >"/dev/stderr"
      exit 1
    }
    if (missing_timeout || timeout_count != reconfigure_count ||
        exec_count != reconfigure_count) {
      printf "FAIL  reconfigure actions=%d timeoutSeconds60=%d exec=%d\n",
        reconfigure_count, timeout_count, exec_count >"/dev/stderr"
      exit 1
    }
    printf "PASS  rendered reconfigure actions=%d timeoutSeconds60=%d\n",
      reconfigure_count, timeout_count
  }
' "$TMP/cmpd.yaml"
