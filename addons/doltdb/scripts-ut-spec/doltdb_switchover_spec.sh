# shellcheck shell=sh

Describe "doltdb-switchover.sh"
  setup() {
    export TEST_DIR
    TEST_DIR="$(mktemp -d)"
    export DOLT_SQL_BIN="${TEST_DIR}/doltdb-sql.sh"
    export DOLT_SWITCHOVER_WAIT_SECONDS="1"
    export DOLT_SWITCHOVER_POLL_SECONDS="1"
    export DOLTDB_SWITCHOVER_LIBRARY_MODE="true"
    export KB_SWITCHOVER_ROLE="primary"
    export KB_SWITCHOVER_CURRENT_NAME="dtdb-repl-doltdb-0"
    export KB_SWITCHOVER_CURRENT_FQDN="dtdb-repl-doltdb-0.dtdb-repl-doltdb-headless.default.svc.cluster.local"
    export KB_SWITCHOVER_CANDIDATE_NAME="dtdb-repl-doltdb-1"
    export KB_SWITCHOVER_CANDIDATE_FQDN="dtdb-repl-doltdb-1.dtdb-repl-doltdb-headless.default.svc.cluster.local"
    export DOLT_POD_FQDN_LIST="${KB_SWITCHOVER_CURRENT_FQDN},${KB_SWITCHOVER_CANDIDATE_FQDN}"
    export CURRENT_ROLE="primary"
    export CURRENT_EPOCH="1"
    export CANDIDATE_ROLE="standby"
    export CANDIDATE_EPOCH="1"
    printf '%s %s\n' "${CURRENT_ROLE}" "${CURRENT_EPOCH}" >"${TEST_DIR}/current.state"
    printf '%s %s\n' "${CANDIDATE_ROLE}" "${CANDIDATE_EPOCH}" >"${TEST_DIR}/candidate.state"

    cat >"${DOLT_SQL_BIN}" <<'EOF'
#!/bin/sh
query="$1"
case "$query" in
  *"SELECT @@GLOBAL.dolt_cluster_role"*)
    if [ "${DOLT_SQL_HOST:-127.0.0.1}" = "${KB_SWITCHOVER_CANDIDATE_FQDN}" ]; then
      read -r role epoch <"${TEST_DIR}/candidate.state"
      printf 'role,epoch\n%s,%s\n' "$role" "$epoch"
    else
      read -r role epoch <"${TEST_DIR}/current.state"
      printf 'role,epoch\n%s,%s\n' "$role" "$epoch"
    fi
    ;;
  *"CALL dolt_assume_cluster_role"*)
    printf '%s|%s\n' "${DOLT_SQL_HOST:-127.0.0.1}" "$query" >>"${TEST_DIR}/calls"
    role="$(printf '%s\n' "$query" | sed "s/.*dolt_assume_cluster_role('\([^']*\)'.*/\1/")"
    epoch="$(printf '%s\n' "$query" | sed 's/.*,[[:space:]]*\([0-9][0-9]*\)).*/\1/')"
    if [ "${DOLT_SQL_HOST:-127.0.0.1}" = "${KB_SWITCHOVER_CANDIDATE_FQDN}" ]; then
      printf '%s %s\n' "$role" "$epoch" >"${TEST_DIR}/candidate.state"
    else
      printf '%s %s\n' "$role" "$epoch" >"${TEST_DIR}/current.state"
    fi
    printf 'status\nok\n'
    ;;
  *)
    printf 'unexpected query: %s\n' "$query" >&2
    exit 1
    ;;
esac
EOF
    chmod +x "${DOLT_SQL_BIN}"
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "$TEST_DIR"
    unset DOLT_SQL_BIN DOLT_SWITCHOVER_WAIT_SECONDS DOLT_SWITCHOVER_POLL_SECONDS DOLT_SWITCHOVER_DEADLINE
    unset DOLTDB_SWITCHOVER_LIBRARY_MODE
    unset KB_SWITCHOVER_ROLE KB_SWITCHOVER_CURRENT_NAME KB_SWITCHOVER_CURRENT_FQDN
    unset KB_SWITCHOVER_CANDIDATE_NAME KB_SWITCHOVER_CANDIDATE_FQDN DOLT_POD_FQDN_LIST
    unset CURRENT_ROLE CURRENT_EPOCH CANDIDATE_ROLE CANDIDATE_EPOCH
  }
  AfterEach "cleanup"

  Include ../scripts/doltdb-switchover.sh

  Describe "main()"
    It "does nothing when KubeBlocks is not switching over a primary role"
      export KB_SWITCHOVER_ROLE="standby"

      When call main
      The status should be success
      The stderr should include "Switchover not for primary role"
      The path "${TEST_DIR}/calls" should not be exist
    End
  End

  Describe "resolve_candidate_fqdn()"
    It "uses the injected candidate FQDN when KubeBlocks provides one"
      When call resolve_candidate_fqdn
      The status should be success
      The output should eq "${KB_SWITCHOVER_CANDIDATE_FQDN}"
    End

    It "selects the first non-current pod FQDN when no candidate is injected"
      unset KB_SWITCHOVER_CANDIDATE_FQDN

      When call resolve_candidate_fqdn
      The status should be success
      The output should eq "dtdb-repl-doltdb-1.dtdb-repl-doltdb-headless.default.svc.cluster.local"
    End
  End

  Describe "run_switchover()"
    It "demotes the current primary before promoting the candidate at the next epoch"
      When call run_switchover
      The status should be success
      The stderr should include "DoltDB switchover completed"
      The contents of file "${TEST_DIR}/calls" should include "127.0.0.1|CALL dolt_assume_cluster_role('standby', 2);"
      The contents of file "${TEST_DIR}/calls" should include "${KB_SWITCHOVER_CANDIDATE_FQDN}|CALL dolt_assume_cluster_role('primary', 2);"
    End

    It "is idempotent when the candidate is already primary and the current pod is already standby"
      export CURRENT_ROLE="standby"
      export CURRENT_EPOCH="2"
      export CANDIDATE_ROLE="primary"
      export CANDIDATE_EPOCH="2"
      printf '%s %s\n' "${CURRENT_ROLE}" "${CURRENT_EPOCH}" >"${TEST_DIR}/current.state"
      printf '%s %s\n' "${CANDIDATE_ROLE}" "${CANDIDATE_EPOCH}" >"${TEST_DIR}/candidate.state"

      When call run_switchover
      The status should be success
      The stderr should include "Switchover already completed"
      The path "${TEST_DIR}/calls" should not be exist
    End

    It "rejects a candidate that is neither standby nor the already-promoted primary"
      export CANDIDATE_ROLE="detected_broken_config"
      printf '%s %s\n' "${CANDIDATE_ROLE}" "${CANDIDATE_EPOCH}" >"${TEST_DIR}/candidate.state"

      When call run_switchover
      The status should be failure
      The stderr should include "detected_broken_config"
    End
  End
End
