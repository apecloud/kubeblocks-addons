# shellcheck shell=sh
#
# E1 contract: the mariadbd command line must start fail-closed with a
# PORTABLE read_only value. NO_LOCK_NO_ADMIN is a runtime-variable enum,
# not a valid command-line boolean — my_getopt does not recognize it and
# silently sets read_only=OFF on every shipped version (verified on
# mariadb 11.4 AND 11.8 via `mariadbd --read-only=NO_LOCK_NO_ADMIN
# --verbose --help` → "boolean value 'NO_LOCK_NO_ADMIN' wasn't recognized.
# Set to OFF."), turning fail-closed intent into a fail-open startup window.
# The SQL path (set_fail_closed_read_only) keeps the NO_LOCK_NO_ADMIN →
# ON → 1 tiering for the stronger runtime fence where the engine supports it.

Describe "replication-entrypoint read_only fail-closed startup contract"
  ENTRYPOINT="${SHELLSPEC_CWD:?}/addons/mariadb/scripts/replication-entrypoint.sh"

  extract_mariadbd_launch() {
    # The bootstrap launch: from the `docker-entrypoint.sh mariadbd \`
    # line to the line ending the backslash-continued argv (bind-address).
    awk '
      /docker-entrypoint\.sh mariadbd \\/ { in_cmd = 1 }
      in_cmd { print }
      in_cmd && /--bind-address=/ { exit }
    ' "${ENTRYPOINT}"
  }

  function_body() {
    awk -v name="$1" '
      $0 ~ "^" name "\\(\\) \\{" { in_fn = 1 }
      in_fn { print }
      in_fn && $0 == "}" { exit }
    ' "${ENTRYPOINT}"
  }

  function_contains() {
    function_body "$1" | grep -F "$2"
  }

  It "starts mariadbd with the portable boolean --read-only=ON"
    When call extract_mariadbd_launch
    The status should be success
    The output should include "--read-only=ON"
  End

  It "does NOT pass the non-portable enum NO_LOCK_NO_ADMIN on the command line"
    When call extract_mariadbd_launch
    The status should be success
    The output should not include "--read-only=NO_LOCK_NO_ADMIN"
  End

  It "keeps the SQL fail-closed helper tiering NO_LOCK_NO_ADMIN -> ON -> 1"
    # Runtime fence via SQL retains the stronger value where supported,
    # then falls back to ON and 1 (both universally valid).
    When run sh -c "grep -A12 'set_fail_closed_read_only()' '${ENTRYPOINT}'"
    The status should be success
    The output should include "SET GLOBAL read_only = NO_LOCK_NO_ADMIN;"
    The output should include "SET GLOBAL read_only = ON;"
    The output should include "SET GLOBAL read_only = 1;"
  End

  It "allows fresh bootstrap seed only on pod-0 with non-empty identity"
    When call function_body "fresh_seed_required_identity_present"
    The status should be success
    The output should include '[ "${POD_INDEX:-}" = "0" ] || return 1'
    The output should include '[ -n "${POD_NAME:-}" ] || return 1'
    The output should include '[ -n "${CLUSTER_NAME:-}" ] || return 1'
    The output should include '[ -n "${COMPONENT_NAME:-}" ] || return 1'
  End

  It "treats leader ConfigMap NotFound as only one explicit fresh-seed gate"
    When call function_body "fresh_seed_leader_configmap_absent"
    The status should be success
    The output should include 'dcs-leader-status --configmap "${leader_cm}" -n "${namespace}"'
    The output should include '1:*" is not found."*) return 0'
    The output should include 'fresh-bootstrap-seed-defer reason=leader-cm-not-absent'
  End

  It "blocks fresh seed when old replica state or recovery markers exist"
    When call function_body "fresh_seed_gate_ready"
    The status should be success
    The output should include '[ "${HAS_EXISTING_DATA:-unknown}" = "false" ] || return 1'
    The output should include '[ ! -f "${DATA_DIR}/master.info" ] || return 1'
    The output should include 'fresh_seed_no_blocking_markers || return 1'
    The output should include 'fresh_seed_slave_status_absent || return 1'
  End

  It "does not treat slave-status query failure as absent"
    When call function_body "fresh_seed_slave_status_absent"
    The status should be success
    The output should include 'rc=$?'
    The output should include 'fresh-bootstrap-seed-defer reason=slave-status-query-failed'
    The output should include 'return 1'
  End

  It "does not treat user-table check failure as fresh"
    When call function_body "local_has_user_tables"
    The status should be success
    The output should include "''|*[!0-9]*)"
    The output should include 'return 0'
  End

  It "re-reads fresh-seed state after checking the leader ConfigMap"
    When call function_body "fresh_seed_gate_ready"
    The status should be success
    The output should include "Re-read local state after the remote/API check"
    The output should include 'reason=user-tables-present-or-unknown-after-reread'
  End

  It "tries fresh pod-0 seed before applying runtime secondary read_only"
    When call function_body "reconcile_sql_listener_for_syncer_secondary_once"
    The status should be success
    The output should include 'try_fresh_bootstrap_seed_once "fresh-bootstrap-seed"'
    The output should include 'set_replica_read_only "runtime-secondary-reconcile"'
  End
End
