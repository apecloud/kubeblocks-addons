# shellcheck shell=sh
# Static gates for semisync recovery behavior in the merged replication CmpD.

Describe "cmpd-replication-merged.yaml semisync startup recovery"
  template_file() {
    printf "%s/addons/mariadb/templates/cmpd-replication-merged.yaml" "${SHELLSPEC_CWD:?}"
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
    before_line="$(grep -n 'syncer-primary-during-replica-rejoin-before-expose' "$(template_file)" | head -1 | cut -d: -f1)"
    after_line="$(grep -n 'syncer-primary-during-replica-rejoin-after-expose' "$(template_file)" | head -1 | cut -d: -f1)"
    fail_closed_line="$(grep -n 'after-expose-not-healthy' "$(template_file)" | head -1 | cut -d: -f1)"
    [ -n "${before_line}" ] && [ -n "${after_line}" ] && [ -n "${fail_closed_line}" ] || return 1
    [ "${before_line}" -lt "${fail_closed_line}" ] && [ "${after_line}" -lt "${fail_closed_line}" ]
  }

  It "defines a merged-CmpD local primary publish readiness gate"
    When call function_contains "local_primary_role_published" ".primary-read-write-ready"
    The status should be success
  End

  It "requires the SQL listener marker before treating local primary as published"
    When call function_contains "local_primary_role_published" ".sql-listener-ready"
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
    When call template_contains 'elif [ -f "{{ .Values.dataMountPath }}/.prestop-fence-started" ]; then'
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
End
