# shellcheck shell=sh
# Static checks for semisync rejoin fences in the rendered runtime template.

Describe "cmpd-replication.yaml rejoin fence template"
  template_file() {
    printf "%s/addons/mariadb/scripts/replication-entrypoint.sh" "${SHELLSPEC_CWD:?}"
  }

  prestop_file() {
    printf "%s/addons/mariadb/scripts/replication-prestop.sh" "${SHELLSPEC_CWD:?}"
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

  publish_rejoin_accepts_syncer_primary_before_defensive_fail_closed() {
    before_line="$(grep -n 'replica-rejoin-before-expose-${label}' "$(template_file)" | head -1 | cut -d: -f1)"
    after_line="$(grep -n 'replica-rejoin-after-expose-${label}' "$(template_file)" | head -1 | cut -d: -f1)"
    fail_closed_line="$(grep -n 'after-expose-not-healthy' "$(template_file)" | head -1 | cut -d: -f1)"
    [ -n "${before_line}" ] && [ -n "${after_line}" ] && [ -n "${fail_closed_line}" ] || return 1
    [ "${before_line}" -lt "${fail_closed_line}" ] && [ "${after_line}" -lt "${fail_closed_line}" ]
  }

  existing_slave_loop_recovers_empty_runtime_slave_status() {
    recover_line="$(grep -n 'recover_empty_existing_slave_config_once "existing-slave-config"' "$(template_file)" | tail -1 | cut -d: -f1)"
    retry_line="$(grep -n 'Existing slave config is not healthy yet' "$(template_file)" | tail -1 | cut -d: -f1)"
    [ -n "${recover_line}" ] && [ -n "${retry_line}" ] || return 1
    [ "${recover_line}" -lt "${retry_line}" ]
  }

  replica_publish_recovers_semisync_slave_before_ready_marker() {
    recover_line="$(grep -n 'recover_semisync_slave_health_after_rejoin' "$(template_file)" | tail -2 | head -1 | cut -d: -f1)"
    ready_line="$(awk -v recover="${recover_line}" 'NR > recover && index($0, "mark_replication_ready") { print NR; exit }' "$(template_file)")"
    [ -n "${recover_line}" ] && [ -n "${ready_line}" ] || return 1
    [ "${recover_line}" -lt "${ready_line}" ]
  }

  replica_lock_checks_syncer_primary_around_read_only() {
    awk '
      index($0, "set_replica_read_only() {") { fn = 1 }
      fn && index($0, "before-lock") { before = NR }
      fn && index($0, "set_fail_closed_read_only \"${label}\"") { readonly = NR }
      fn && index($0, "after-read-only") { after = NR }
      fn && index($0, "set-replica-read-only label=${label}") { exit(before && readonly && after && before < readonly && readonly < after ? 0 : 1) }
      END { exit(before && readonly && after && before < readonly && readonly < after ? 0 : 1) }
    ' "$(template_file)"
  }

  publish_rejoin_accepts_syncer_primary_during_lock() {
    awk '
      index($0, "publish_replica_after_rejoin_ready() {") { fn = 1 }
      fn && index($0, "replica-rejoin-before-expose-lock-${label}") { before_lock = NR }
      fn && index($0, "replica-rejoin-after-expose-lock-${label}") { after_lock = NR }
      fn && index($0, "recover_semisync_slave_health_after_rejoin") { recover = NR; exit }
      END { exit(before_lock && after_lock && recover && before_lock < recover && after_lock < recover ? 0 : 1) }
    ' "$(template_file)"
  }

  runtime_secondary_reconcile_accepts_syncer_primary_during_lock() {
    awk '
      index($0, "reconcile_sql_listener_for_syncer_secondary_once() {") { fn = 1 }
      fn && index($0, "set_replica_read_only \"runtime-secondary-reconcile\"") { lock = NR }
      fn && index($0, "runtime-secondary-reconcile-lock") { accept = NR }
      fn && index($0, "runtime-secondary-listener-reconcile-ready") { ready = NR; exit }
      END { exit(lock && accept && ready && lock < accept && accept < ready ? 0 : 1) }
    ' "$(template_file)"
  }

  runtime_secondary_reconcile_publishes_healthy_slave_through_listener_gate() {
    awk '
      index($0, "reconcile_sql_listener_for_syncer_secondary_once() {") { fn = 1 }
      fn && index($0, "slave_status_is_healthy") { healthy = NR }
      fn && index($0, "publish_replica_after_rejoin_ready \"runtime-secondary-reconcile\"") { publish = NR }
      fn && index($0, "runtime-secondary-listener-reconcile-ready") { ready = NR }
      fn && index($0, "runtime-secondary-listener-reconcile-pending-after-publish") { pending = NR; exit }
      END { exit(healthy && publish && ready && pending && healthy < publish && publish < ready && ready < pending ? 0 : 1) }
    ' "$(template_file)"
  }

  secondary_expose_fast_path_requires_real_wildcard_listener() {
    awk '
      index($0, "expose_sql_listener_for_safe_role() {") { fn = 1 }
      fn && index($0, ".sql-listener-ready") && index($0, "mariadbd_listen_on_all_interfaces") { found = 1 }
      fn && index($0, "sql-listener-expose-stale-marker") { stale = 1 }
      fn && index($0, "sql-listener-expose-begin") { exit(found && stale ? 0 : 1) }
      END { exit(found && stale ? 0 : 1) }
    ' "$(template_file)"
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

  It "clears stale preStop fence markers only on the first startup attempt in a container lifecycle"
    When call template_contains 'LIFECYCLE_MARKER="/tmp/.mariadb-startup-lifecycle"'
    The status should be success
    The output should include "/tmp/.mariadb-startup-lifecycle"
  End

  It "logs startup-time cleanup of stale PVC preStop markers"
    When call template_contains "clear-stale-prestop-fence-on-container-start"
    The status should be success
    The output should include "clear-stale-prestop-fence-on-container-start"
  End

  It "keeps the preStop fence on later startup attempts in the same container lifecycle"
    When call template_contains 'elif [ -f "${DATA_DIR}/.prestop-fence-started" ]; then'
    The status should be success
    The output should include ".prestop-fence-started"
  End

  It "logs refusal when preStop fence appears after the lifecycle marker exists"
    When call template_contains "decision=refuse-restart-after-prestop"
    The status should be success
    The output should include "refuse-restart-after-prestop"
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

  It "alpha.64 v1: locks local root without granting table writes AND without admin-bypass SUPER (use CMPD_SECONDARY_FENCE_GRANT_BODY constant)"
    # alpha.64 v1 (Jack 09:35 RED root cause): SUPER is admin bypass; dropped
    # from secondary fence grant body. Grant body now sourced from
    # CMPD_SECONDARY_FENCE_GRANT_BODY constant (SELECT, PROCESS, RELOAD,
    # REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN).
    When call template_contains "GRANT \${CMPD_SECONDARY_FENCE_GRANT_BODY} ON *.* TO '\${user}'@'\${host}';"
    The status should be success
    The output should include "GRANT \${CMPD_SECONDARY_FENCE_GRANT_BODY}"
  End

  It "alpha.64 v1: secondary fence grant body constant explicitly excludes SUPER (alpha.81 v1: insert SLAVE MONITOR between REPLICATION CLIENT and REPLICATION MASTER ADMIN for MariaDB 11.4 SHOW SLAVE STATUS support)"
    When call template_contains 'CMPD_SECONDARY_FENCE_GRANT_BODY="SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, SLAVE MONITOR, REPLICATION MASTER ADMIN"'
    The status should be success
    The output should include "CMPD_SECONDARY_FENCE_GRANT_BODY"
  End

  It "keeps syncer local root semisync dynamic privileges while table writes are fenced"
    When call function_contains "grant_optional_local_root_privileges" "REPLICATION MASTER ADMIN"
    The status should be success
  End

  It "locks local root after putting a replica into read-only"
    When call function_contains "set_replica_read_only" "lock_local_root_writes \"\${label}\""
    The status should be success
  End

  It "clears stale primary readiness before publishing a replica"
    When call function_contains "set_replica_read_only" ".primary-read-write-ready"
    The status should be success
  End

  It "unlocks local root before publishing a primary as writable"
    When call function_contains "set_primary_read_write" "unlock_local_root_writes \"\${label}\""
    The status should be success
  End

  It "probes local root table writes before publishing a primary as writable"
    When call function_contains "primary_write_gates_ready" "primary_local_root_write_ready"
    The status should be success
  End

  It "probes internal root table writes before publishing a primary as writable"
    When call function_contains "primary_write_gates_ready" "primary_internal_root_write_ready"
    The status should be success
  End

  It "requires local root unlock before publishing a primary as writable"
    When call function_contains "set_primary_read_write" "primary-read-write local-root-unlock rc=1"
    The status should be success
  End

  It "requires remote root unlock before publishing a primary as writable"
    When call function_contains "set_primary_read_write" "fail_primary_read_write_gate \"\${label}\" \"remote-root-unlock\""
    The status should be success
  End

  It "records failed primary write gates before publishing a primary as writable"
    When call function_contains "fail_primary_read_write_gate" "primary-read-write \${reason} rc=1"
    The status should be success
  End

  It "re-fences remote root when a primary write gate fails"
    When call function_contains "fail_primary_read_write_gate" "lock_remote_root_writes"
    The status should be success
  End

  It "fails closed when read_only cannot be opened for a primary"
    When call function_contains "set_primary_read_write" "fail_primary_read_write_gate \"\${label}\" \"read-only-open\""
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
    When call grep -F "lock_local_root_for_prestop \"prestop\" \"socket\"" "$(prestop_file)"
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

  # [REMOVED] Test for "primary-service-routes-to-peer" — this pattern was
  # removed during CMPD consolidation (PR #2933).

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

  It "accepts syncer primary promotion inside replica rejoin before fail-closing as replica"
    When call publish_rejoin_accepts_syncer_primary_before_defensive_fail_closed
    The status should be success
  End

  It "defines semisync slave health recovery after replication rejoin"
    When call template_contains "recover_semisync_slave_health_after_rejoin()"
    The status should be success
    The output should include "recover_semisync_slave_health_after_rejoin"
  End

  It "restarts the slave IO thread when semisync slave status stays OFF"
    When call template_contains "STOP SLAVE IO_THREAD; START SLAVE IO_THREAD;"
    The status should be success
    The output should include "START SLAVE IO_THREAD"
  End

  It "recovers semisync slave health before publishing replica rejoin readiness"
    When call replica_publish_recovers_semisync_slave_before_ready_marker
    The status should be success
  End

  It "checks syncer primary before and after fail-closed read_only in replica lock"
    When call replica_lock_checks_syncer_primary_around_read_only
    The status should be success
  End

  It "accepts syncer primary promotion while publish path is inside replica lock"
    When call publish_rejoin_accepts_syncer_primary_during_lock
    The status should be success
  End

  It "accepts syncer primary promotion while runtime secondary reconcile is inside replica lock"
    When call runtime_secondary_reconcile_accepts_syncer_primary_during_lock
    The status should be success
  End

  It "publishes a healthy runtime secondary through the SQL listener gate"
    When call runtime_secondary_reconcile_publishes_healthy_slave_through_listener_gate
    The status should be success
  End

  It "does not trust .sql-listener-ready without a real wildcard listener in syncer-secondary expose path"
    When call secondary_expose_fast_path_requires_real_wildcard_listener
    The status should be success
  End

  It "logs replica rejoin handoff to syncer primary publication"
    When call template_contains "action=accept-primary-promotion"
    The status should be success
    The output should include "accept-primary-promotion"
  End

  It "keeps pod-0 blocked self-election in a reconcile loop instead of exiting permanently"
    When call template_contains "pod-0 startup: blocked self-election, awaiting syncer promotion or primary Service"
    The status should be success
    The output should include "blocked self-election"
  End

  It "lets pod-0 accept syncer primary promotion after blocked self-election"
    When call template_contains "pod-0 accepted syncer primary promotion after blocked self-election"
    The status should be success
    The output should include "accepted syncer primary promotion"
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

  It "defines an existing-slave runtime-status recovery helper"
    When call function_contains "recover_empty_existing_slave_config_once" "empty-runtime-slave-status"
    The status should be success
  End

  It "reconfigures existing slave config when runtime slave status disappears"
    When call existing_slave_loop_recovers_empty_runtime_slave_status
    The status should be success
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

  # [REMOVED] Test for clear_local_kb_health_check_table — this function was
  # removed during CMPD consolidation (PR #2933).

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

  # [REMOVED] Tests for repair_kb_health_check_replication_error,
  # with_local_read_write_for_health_check_repair,
  # slave_status_has_kb_health_check_repairable_error, and
  # "fresh-health-check-cleanup-failed" — these functions/patterns were
  # removed during CMPD consolidation (PR #2933).

  It "uses the internal admin for preStop SQL so root can stay fenced"
    When call grep -F "mariadb -u\"\${INTERNAL_ROOT_USER}\" -p\"\${MARIADB_ROOT_PASSWORD}\"" "$(prestop_file)"
    The status should be success
    The output should include "INTERNAL_ROOT_USER"
  End
End
