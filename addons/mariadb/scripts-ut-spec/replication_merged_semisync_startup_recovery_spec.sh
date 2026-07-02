# shellcheck shell=sh
# Static gates for semisync recovery behavior in the merged replication CmpD.

Describe "cmpd-replication.yaml semisync startup recovery"
  template_file() {
    printf "%s/addons/mariadb/scripts/replication-entrypoint.sh" "${SHELLSPEC_CWD:?}"
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

  no_primary_loop_reconciles_syncer_primary_before_block() {
    awk '
      /no_primary_deadline=/ { branch = 1 }
      branch && /while \[ \$SECONDS -lt \$no_primary_deadline \]/ { loop = 1 }
      loop && /reconcile_sql_listener_for_syncer_primary_once \|\| true/ { reconcile = NR }
      branch && /block_existing_datadir_self_election_without_primary/ { block = NR; exit }
      END { exit(reconcile && block && reconcile < block ? 0 : 1) }
    ' "$(template_file)"
  }

  publish_rejoin_accepts_syncer_primary_before_defensive_fail_closed() {
    before_line="$(grep -n 'replica-rejoin-before-expose-${label}' "$(template_file)" | head -1 | cut -d: -f1)"
    after_line="$(grep -n 'replica-rejoin-after-expose-${label}' "$(template_file)" | head -1 | cut -d: -f1)"
    fail_closed_line="$(grep -n 'after-expose-not-healthy' "$(template_file)" | head -1 | cut -d: -f1)"
    [ -n "${before_line}" ] && [ -n "${after_line}" ] && [ -n "${fail_closed_line}" ] || return 1
    [ "${before_line}" -lt "${fail_closed_line}" ] && [ "${after_line}" -lt "${fail_closed_line}" ]
  }

  default_pod0_primary_failure_marks_pending_before_runtime_reconcile() {
    fail_line="$(grep -n 'Default pod-0 primary publish failed; entering runtime role reconcile loop' "$(template_file)" | head -1 | cut -d: -f1)"
    pending_line="$(awk -v fail_line="${fail_line}" 'NR < fail_line && index($0, "mark_replication_pending") { line = NR } END { if (line) print line }' "$(template_file)")"
    runtime_line="$(grep -n 'wait_for_mariadbd_with_role_reconcile' "$(template_file)" | tail -1 | cut -d: -f1)"
    [ -n "${fail_line}" ] && [ -n "${pending_line}" ] && [ -n "${runtime_line}" ] || return 1
    [ "${pending_line}" -lt "${fail_line}" ] && [ "${fail_line}" -lt "${runtime_line}" ]
  }

  stale_prestop_cleanup_clears_role_publish_markers() {
    awk '
      index($0, "decision=clear-stale-prestop-fence-on-container-start") { block = 1 }
      block && index($0, "rm -f ${DATA_DIR}/.prestop-fence-started") { rmblock = 1 }
      rmblock && index($0, "${DATA_DIR}/.sql-listener-ready") { sql = 1 }
      rmblock && index($0, "${DATA_DIR}/.primary-read-write-ready") { primary = 1 }
      rmblock && index($0, "${DATA_DIR}/.replication-ready") { replica = 1 }
      block && index($0, "elif [ -f \"${DATA_DIR}/.prestop-fence-started\" ]; then") { exit }
      END { exit(sql && primary && replica ? 0 : 1) }
    ' "$(template_file)"
  }

  local_primary_role_publish_requires_real_wildcard_listener() {
    awk '
      index($0, "local_primary_role_published() {") { fn = 1 }
      fn && index($0, ".sql-listener-ready") { marker = 1 }
      fn && index($0, "mariadbd_listen_on_all_interfaces") { listener = 1 }
      fn && /^            }$/ { exit(marker && listener ? 0 : 1) }
      END { exit(marker && listener ? 0 : 1) }
    ' "$(template_file)"
  }

  primary_reconcile_fast_path_requires_real_wildcard_listener() {
    awk '
      index($0, "reconcile_sql_listener_for_syncer_primary_once() {") { fn = 1 }
      fn && index($0, ".primary-read-write-ready") && index($0, "mariadbd_listen_on_all_interfaces") { found = 1 }
      fn && index($0, "runtime-primary-listener-reconcile-repair-begin") { exit(found ? 0 : 1) }
      END { exit(found ? 0 : 1) }
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

  no_slave_startup_loop_reconciles_syncer_primary_even_with_stale_listener_marker() {
    awk '
      index($0, "elif [ -n \"${PRIMARY_SID}\" ] || [ \"${POD_INDEX}\" -gt 0 ]; then") { branch = 1 }
      branch && index($0, "while true; do") { loop = 1 }
      loop && index($0, "if [ -z \"${PRIMARY_SID}\" ] || [ \"${PRIMARY_SID}\" = \"${SERVICE_ID}\" ]; then") { no_primary = 1 }
      no_primary && index($0, "if [ ! -f \"${DATA_DIR}/.sql-listener-ready\" ]; then") { stale_guard = 1 }
      no_primary && index($0, "reconcile_sql_listener_for_syncer_primary_once || true") { reconcile = 1 }
      no_primary && index($0, "_no_primary_iters=") { exit(reconcile && !stale_guard ? 0 : 1) }
      END { exit(reconcile && !stale_guard ? 0 : 1) }
    ' "$(template_file)"
  }

  existing_slave_loop_recovers_empty_runtime_slave_status() {
    awk '
      index($0, "if [ -n \"${PRIMARY_SID}\" ] && [ \"${PRIMARY_SID}\" != \"${SERVICE_ID}\" ]; then") { branch = 1 }
      branch && index($0, "while true; do") { loop = 1 }
      loop && index($0, "publish_replica_after_rejoin_ready \"existing-slave-config\"") { publish = NR }
      loop && index($0, "recover_empty_existing_slave_config_once \"existing-slave-config\"") { recover = NR }
      loop && index($0, "Existing slave config is not healthy yet") { retry = NR; exit }
      END { exit(publish && recover && retry && publish < recover && recover < retry ? 0 : 1) }
    ' "$(template_file)"
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

  It "defines a merged-CmpD local primary publish readiness gate"
    When call function_contains "local_primary_role_published" ".primary-read-write-ready"
    The status should be success
  End

  It "requires the SQL listener marker before treating local primary as published"
    When call function_contains "local_primary_role_published" ".sql-listener-ready"
    The status should be success
  End

  It "requires a real wildcard listener before treating local primary as published"
    When call local_primary_role_publish_requires_real_wildcard_listener
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

  It "clears stale role and SQL listener markers together with stale PVC preStop markers"
    When call stale_prestop_cleanup_clears_role_publish_markers
    The status should be success
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

  It "reconciles local syncer primary during the pod-0 no-primary startup loop before blocking self-election"
    When call no_primary_loop_reconciles_syncer_primary_before_block
    The status should be success
  End

  It "does not trust .sql-listener-ready without a real wildcard listener in syncer-primary fast path"
    When call primary_reconcile_fast_path_requires_real_wildcard_listener
    The status should be success
  End

  It "does not trust .sql-listener-ready without a real wildcard listener in syncer-secondary expose path"
    When call secondary_expose_fast_path_requires_real_wildcard_listener
    The status should be success
  End

  It "runs syncer-primary reconcile even when .sql-listener-ready already exists in the no-slave startup loop"
    When call no_slave_startup_loop_reconciles_syncer_primary_even_with_stale_listener_marker
    The status should be success
  End

  It "defines an existing-slave runtime-status recovery helper"
    When call function_contains "recover_empty_existing_slave_config_once" "empty-runtime-slave-status"
    The status should be success
  End

  It "reconfigures existing slave config when runtime slave status disappears"
    When call existing_slave_loop_recovers_empty_runtime_slave_status
    The status should be success
  End

  It "does not enter the no-primary fail-closed path after local syncer primary is published"
    When call template_contains 'if [ -z "${PRIMARY_SID}" ] && ! local_primary_role_published; then'
    The status should be success
    The output should include "local_primary_role_published"
  End

  It "records the stop/start recovery handoff in startup logs"
    When call template_contains "accepted local syncer primary promotion while Primary Service is empty"
    The status should be success
    The output should include "accepted local syncer primary promotion"
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

  It "does not block forever when default pod-0 primary publish fails"
    When call template_contains "Default pod-0 primary publish failed; entering runtime role reconcile loop"
    The status should be success
    The output should include "runtime role reconcile loop"
  End

  It "keeps default pod-0 primary publish failure pending for runtime reconcile"
    When call default_pod0_primary_failure_marks_pending_before_runtime_reconcile
    The status should be success
  End
End
