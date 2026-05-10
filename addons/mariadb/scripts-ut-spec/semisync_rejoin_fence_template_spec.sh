# shellcheck shell=sh
# Static checks for semisync rejoin fences in the rendered runtime template.

Describe "cmpd-semisync.yaml rejoin fence template"
  template_file() {
    printf "%s/addons/mariadb/templates/cmpd-semisync.yaml" "${SHELLSPEC_CWD:?}"
  }

  template_contains() {
    grep -F "$1" "$(template_file)"
  }

  function_contains() {
    function_name="$1"
    expected="$2"
    awk -v function_name="${function_name}" -v expected="${expected}" '
      $0 ~ "^[[:space:]]*" function_name "\\(\\) \\{" { inside = 1 }
      inside && index($0, expected) > 0 { found = 1 }
      inside && /^[[:space:]]*}/ { exit }
      END { exit(found ? 0 : 1) }
    ' "$(template_file)"
  }

  wait_loop_queries_primary_before_reconcile() {
    primary_query_line="$(grep -n 'PRIMARY_SID=$(timeout 10 mariadb' "$(template_file)" | tail -1 | cut -d: -f1)"
    reconcile_line="$(grep -n 'reconcile_sql_listener_for_syncer_primary_once || true' "$(template_file)" | tail -1 | cut -d: -f1)"
    [ -n "${primary_query_line}" ] && [ -n "${reconcile_line}" ] || return 1
    [ "${primary_query_line}" -lt "${reconcile_line}" ]
  }

  runtime_secondary_follow_starts_io_before_health_cleanup() {
    begin_line="$(grep -n 'runtime-secondary-follow-configure-begin' "$(template_file)" | head -1 | cut -d: -f1)"
    io_line="$(awk -v begin="${begin_line}" 'NR > begin && index($0, "START SLAVE IO_THREAD;") { print NR; exit }' "$(template_file)")"
    cleanup_line="$(awk -v begin="${begin_line}" 'NR > begin && index($0, "prepare_fresh_replica_for_sql_thread_start") { print NR; exit }' "$(template_file)")"
    [ -n "${begin_line}" ] && [ -n "${io_line}" ] && [ -n "${cleanup_line}" ] || return 1
    [ "${begin_line}" -lt "${io_line}" ] && [ "${io_line}" -lt "${cleanup_line}" ]
  }

  It "declares an internal local admin before fencing user-facing root"
    When call template_contains 'MARIADB_INTERNAL_ROOT_USER="${MARIADB_INTERNAL_ROOT_USER:-kb_internal_root}"'
    The status should be success
    The output should include "MARIADB_INTERNAL_ROOT_USER"
  End

  It "waits for internal admin readiness before startup role decision"
    When call template_contains 'wait_for_internal_local_admin "startup-before-role-decision"'
    The status should be success
    The output should include "startup-before-role-decision"
  End

  It "does not ignore startup internal admin setup failure"
    When call template_contains 'ensure_internal_local_admin "startup-before-role-decision" || true'
    The status should be failure
  End

  It "selects internal admin only after a successful probe"
    When call function_contains "wait_for_internal_local_admin" "probe_internal_local_admin"
    The status should be success
  End

  It "grants internal admin the semisync promote dynamic privilege"
    When call function_contains "grant_internal_admin_runtime_privileges" "REPLICATION SLAVE ADMIN"
    The status should be success
  End

  It "requires internal admin promote privilege before role publishing"
    When call function_contains "wait_for_internal_local_admin" "internal_local_admin_has_required_privileges"
    The status should be success
  End

  It "requires internal admin primary semisync dynamic privilege before role publishing"
    When call function_contains "internal_local_admin_has_required_privileges" "REPLICATION_MASTER_ADMIN"
    The status should be success
  End

  It "requires internal admin read-only dynamic privilege before role publishing"
    When call function_contains "internal_local_admin_has_required_privileges" "READ_ONLY_ADMIN"
    The status should be success
  End

  It "keeps role publishing pending while internal admin is unavailable"
    When call function_contains "wait_for_internal_local_admin" "mark_replication_pending"
    The status should be success
  End

  It "defines the local root state helper"
    When call template_contains "set_local_root_account_state()"
    The status should be success
    The output should include "set_local_root_account_state"
  End

  It "defines the local root lock helper"
    When call template_contains "lock_local_root_writes()"
    The status should be success
    The output should include "lock_local_root_writes"
  End

  It "defines the local root unlock helper"
    When call template_contains "unlock_local_root_writes()"
    The status should be success
    The output should include "unlock_local_root_writes"
  End

  It "locks local root without granting table writes"
    When call template_contains "GRANT SELECT, PROCESS, RELOAD, SUPER, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO '\${user}'@'\${host}';"
    The status should be success
    The output should include "GRANT SELECT, PROCESS, RELOAD, SUPER"
  End

  It "keeps remote root follow privileges while table writes are fenced"
    When call template_contains "GRANT SELECT, PROCESS, RELOAD, SUPER, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO '\${user}'@'\${host}';"
    The status should be success
    The output should include "REPLICATION MASTER ADMIN"
  End

  It "keeps syncer local root semisync dynamic privileges while table writes are fenced"
    When call function_contains "grant_optional_local_root_privileges" "REPLICATION MASTER ADMIN"
    The status should be success
  End

  It "locks local root after putting a replica into read-only"
    When call function_contains "set_replica_read_only" "lock_local_root_writes \"replica-read-only\""
    The status should be success
  End

  It "clears stale primary readiness before publishing a replica"
    When call function_contains "set_replica_read_only" ".primary-read-write-ready"
    The status should be success
  End

  It "unlocks local root before publishing a primary as writable"
    When call function_contains "set_primary_read_write" "unlock_local_root_writes \"primary-read-write\""
    The status should be success
  End

  It "probes local root table writes before publishing a primary as writable"
    When call function_contains "set_primary_read_write" "primary_local_root_write_ready \"primary-read-write\""
    The status should be success
  End

  It "requires local root unlock before publishing a primary as writable"
    When call function_contains "set_primary_read_write" "primary-read-write local-root-unlock rc=1"
    The status should be success
  End

  It "marks primary read-write readiness after local root and read_only are fixed"
    When call function_contains "set_primary_read_write" ".primary-read-write-ready"
    The status should be success
  End

  It "clears stale remote-root fence markers before publishing a primary as writable"
    When call function_contains "set_primary_read_write" ".remote-root-fence-role"
    The status should be success
  End

  It "clears primary read-write readiness when replication becomes pending"
    When call function_contains "mark_replication_pending" ".primary-read-write-ready"
    The status should be success
  End

  It "clears stale remote-root fence markers when replication becomes pending"
    When call function_contains "mark_replication_pending" ".remote-root-fence-role"
    The status should be success
  End

  It "keeps unresolved startup locally fenced"
    When call template_contains "lock_local_root_writes \"startup-before-role-decision\""
    The status should be success
    The output should include "startup-before-role-decision"
  End

  It "pre-locks local root before remote-root startup fencing"
    When call template_contains "lock_local_root_writes \"startup-before-role-decision-pre-remote\""
    The status should be success
    The output should include "startup-before-role-decision-pre-remote"
  End

  It "does not unlock local root as a remote-root helper side effect"
    When call template_contains "ensure_local_root_accounts"
    The status should be failure
  End

  It "locks local root persistently in preStop"
    When call template_contains "lock_local_root_for_prestop \"prestop\" \"socket\""
    The status should be success
    The output should include "lock_local_root_for_prestop"
  End

  It "keeps unresolved wait-loop roles locally fenced"
    When call template_contains "lock_local_root_writes \"wait-primary-loop-entry\""
    The status should be success
    The output should include "wait-primary-loop-entry"
  End

  It "queries the Primary Service before accepting syncer primary in the wait loop"
    When call wait_loop_queries_primary_before_reconcile
    The status should be success
  End

  It "defers fresh non-pod0 syncer primary promotion during bootstrap grace"
    When call template_contains "runtime-primary-listener-reconcile-defer reason=fresh-bootstrap-grace"
    The status should be success
    The output should include "fresh-bootstrap-grace"
  End

  It "defers syncer primary promotion when the Primary Service already reaches a peer"
    When call template_contains "runtime-primary-listener-reconcile-defer reason=primary-service-routes-to-peer"
    The status should be success
    The output should include "primary-service-routes-to-peer"
  End

  It "repairs a syncer primary whose SQL listener is exposed before local write access is ready"
    When call function_contains "reconcile_sql_listener_for_syncer_primary_once" "primary-role-state-drift"
    The status should be success
  End

  It "exposes syncer-promoted primary only after primary local write access is ready"
    When call function_contains "reconcile_sql_listener_for_syncer_primary_once" "expose_sql_listener_for_primary_role \"syncer-promoted-primary\""
    The status should be success
  End

  It "marks an already exposed syncer primary pending if local writes are not ready"
    When call function_contains "expose_sql_listener_for_primary_role" "existing-listener-local-write-not-ready"
    The status should be success
  End

  It "resets stale slave config when an already exposed listener becomes primary"
    When call function_contains "expose_sql_listener_for_primary_role" "STOP SLAVE; RESET SLAVE ALL"
    The status should be success
  End

  It "reconciles already exposed syncer primary when stale slave files remain"
    When call function_contains "reconcile_sql_listener_for_syncer_primary_once" "master.info"
    The status should be success
  End

  It "lets an existing slave config accept syncer primary promotion before retrying replica recovery"
    When call template_contains "Existing slave config accepted syncer primary promotion"
    The status should be success
    The output should include "Existing slave config accepted syncer primary promotion"
  End

  It "reconciles syncer secondary into fail-closed local SQL state"
    When call function_contains "reconcile_sql_listener_for_syncer_secondary_once" "set_replica_read_only"
    The status should be success
  End

  It "keeps syncer secondary unpublished until replication is healthy"
    When call function_contains "reconcile_sql_listener_for_syncer_secondary_once" "mark_replication_pending"
    The status should be success
  End

  It "lets syncer secondary actively configure replication to the Primary Service"
    When call template_contains "runtime-secondary-follow-configure-begin"
    The status should be success
    The output should include "runtime-secondary-follow-configure-begin"
  End

  It "starts runtime secondary IO before local health cleanup"
    When call runtime_secondary_follow_starts_io_before_health_cleanup
    The status should be success
  End

  It "publishes syncer secondary only after runtime follow becomes healthy"
    When call template_contains "runtime-secondary-listener-reconcile-ready-after-configure"
    The status should be success
    The output should include "runtime-secondary-listener-reconcile-ready-after-configure"
  End

  It "keeps runtime secondary follow blocked on user-table GTID divergence"
    When call template_contains "runtime-secondary-follow-configure-blocked label=\${label} reason=gtid-divergence"
    The status should be success
    The output should include "runtime-secondary-follow-configure-blocked"
  End

  It "runs secondary reconciliation in the runtime wait loop"
    When call function_contains "wait_for_mariadbd_with_role_reconcile" "reconcile_sql_listener_for_syncer_secondary_once"
    The status should be success
  End

  It "keeps no-primary paths locally fenced"
    When call function_contains "block_existing_datadir_self_election_without_primary" "lock_local_root_writes \"no-primary-existing-datadir\""
    The status should be success
  End

  It "keeps GTID divergence paths locally fenced"
    When call function_contains "fail_closed_for_gtid_divergence" "lock_local_root_writes \"gtid-divergence\""
    The status should be success
  End

  It "defines fresh replica health check table preparation before SQL-thread replication"
    When call function_contains "clear_local_kb_health_check_table" "CREATE TABLE IF NOT EXISTS kubeblocks.kb_health_check"
    The status should be success
  End

  It "starts fresh replica IO before local health cleanup"
    When call template_contains "START SLAVE IO_THREAD;"
    The status should be success
    The output should include "START SLAVE IO_THREAD"
  End

  It "starts fresh replica SQL after local health cleanup"
    When call template_contains "START SLAVE SQL_THREAD;"
    The status should be success
    The output should include "START SLAVE SQL_THREAD"
  End

  It "repairs kubeblocks health check replication errors before publishing replica readiness"
    When call function_contains "repair_kb_health_check_replication_error" "prepared-local-kb-health-check-after-replication-error"
    The status should be success
  End

  It "treats missing kubeblocks health table as repairable during fresh follow"
    When call function_contains "slave_status_has_kb_health_check_repairable_error" "Last_SQL_Errno: 1146"
    The status should be success
  End

  It "keeps failed fresh health cleanup locally fenced"
    When call template_contains "lock_local_root_writes \"fresh-health-check-cleanup-failed\""
    The status should be success
    The output should include "fresh-health-check-cleanup-failed"
  End

  It "uses the internal admin for preStop SQL so root can stay fenced"
    When call template_contains "mariadb -u\"\${INTERNAL_ROOT_USER}\" -p\"\${MARIADB_ROOT_PASSWORD}\""
    The status should be success
    The output should include "INTERNAL_ROOT_USER"
  End
End
