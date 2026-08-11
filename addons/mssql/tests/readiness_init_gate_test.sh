#!/usr/bin/env bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

# Source contract for the MSSQL Pod readiness gate. Cluster Running must not
# expose a Pod as Ready before entrypoint initialization has installed the AG,
# triggers, stored procedures, and Service Broker objects.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CMPD_FILE="$ROOT/templates/cmpd.yaml"
SCRIPTS_TEMPLATE="$ROOT/templates/scripts.yaml"
READINESS_SCRIPT="$ROOT/scripts/readiness_probe.sh"

contains_file() {
  local pattern=$1
  grep -Fq -- "$pattern" "$CMPD_FILE"
}

case_readiness_waits_for_init_flag() {
  contains_file 'readinessProbe:' || return 1
  grep -Fq -- 'MSSQL_INIT_FLAG="${MSSQL_INIT_FLAG:-/var/opt/mssql/.initialized}"' "$READINESS_SCRIPT" || return 1
  grep -Fq -- 'if [ ! -f "$MSSQL_INIT_FLAG" ]; then' "$READINESS_SCRIPT" || return 1
}

case_readiness_uses_script_from_configmap() {
  contains_file '/scripts/readiness_probe.sh >/dev/null' || return 1
  grep -Fq -- 'readiness_probe.sh: |' "$SCRIPTS_TEMPLATE" || return 1
  grep -Fq -- '.Files.Get "scripts/readiness_probe.sh"' "$SCRIPTS_TEMPLATE" || return 1
}

case_readiness_checks_local_sqlserver_with_contract() {
  grep -Fq -- 'SQLCMD="${SQLCMD:-/opt/mssql-tools18/bin/sqlcmd}"' "$READINESS_SCRIPT" || return 1
  grep -Fq -- '-S "127.0.0.1,${MSSQL_SERVER_PORT}"' "$READINESS_SCRIPT" || return 1
  grep -Fq -- '-U "$MSSQL_SA_USER"' "$READINESS_SCRIPT" || return 1
  grep -Fq -- '-P "$MSSQL_SA_PASSWORD"' "$READINESS_SCRIPT" || return 1
  grep -Fq -- '-C -b -V 11' "$READINESS_SCRIPT" || return 1
  grep -Fq -- '-l "$MSSQL_READINESS_LOGIN_TIMEOUT"' "$READINESS_SCRIPT" || return 1
  grep -Fq -- '-t "$MSSQL_READINESS_QUERY_TIMEOUT"' "$READINESS_SCRIPT" || return 1
  grep -Fq -- 'master.dbo.sp_ape_sync_db_to_ag' "$READINESS_SCRIPT" || return 1
  grep -Fq -- 'master.dbo.sp_ape_sync_login' "$READINESS_SCRIPT" || return 1
  grep -Fq -- 'enabled server trigger _$$_tr_$$_ape_create_database' "$READINESS_SCRIPT" || return 1
  grep -Fq -- 'enabled server trigger _$$_tr_$$_ape_create_login' "$READINESS_SCRIPT" || return 1
  grep -Fq -- 'active Service Broker queue ApeSyncDBTarget' "$READINESS_SCRIPT" || return 1
  grep -Fq -- 'active Service Broker queue ApeSyncLoginTarget' "$READINESS_SCRIPT" || return 1
}

case_readiness_is_bounded() {
  contains_file 'initialDelaySeconds: 5' || return 1
  contains_file 'periodSeconds: 5' || return 1
  contains_file 'timeoutSeconds: 5' || return 1
  contains_file 'failureThreshold: 3' || return 1
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

run_case "readiness waits for the entrypoint init flag" case_readiness_waits_for_init_flag
run_case "readiness uses the injected readiness script" case_readiness_uses_script_from_configmap
run_case "readiness checks local SQL Server object contract with short timeouts" case_readiness_checks_local_sqlserver_with_contract
run_case "readiness probe timings are bounded" case_readiness_is_bounded

echo
echo "Total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
