# shellcheck shell=sh

Describe "MariaDB replication Syncer timing contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/mariadb" "$(repo_root)"
  }

  rendered_syncer_ttl() {
    helm template test-addon "$(chart_path)" |
      awk '/name: KB_TTL/{getline; sub(/^[[:space:]]+value:[[:space:]]*/, ""); gsub(/"/, ""); print; exit}'
  }

  It "sets a 30 second lease TTL on the replication Syncer container"
    When call rendered_syncer_ttl
    The output should equal "30"
  End

  It "keeps the Syncer cycle budget above the MariaDB 15 second empty-GTID stability wait"
    ttl=$(rendered_syncer_ttl)
    cycle_budget=$((ttl * 2 / 3))
    When call test "${cycle_budget}" -gt 15
    The status should be success
  End

  It "keeps termination grace above demote, lease release, and TTL yield"
    ttl=$(rendered_syncer_ttl)
    grace=$(helm template test-addon "$(chart_path)" |
      awk '/terminationGracePeriodSeconds:/{print $2; exit}')
    required=$((10 + 5 + ttl))
    When call test "${grace}" -gt "${required}"
    The status should be success
  End

  It "configures the MariaDB-specific HA startup safety gate"
    When call sh -c 'helm template test-addon "$1" | grep -A5 "name: KB_MARIADB_HA_STARTUP_GATE_FILE" | grep -q "/tmp/.syncer-ha-ready"' sh "$(chart_path)"
    The status should be success
  End

  It "releases the HA startup gate only after fail-closed read_only"
    script="$(chart_path)/scripts/replication-entrypoint.sh"
    fence_line=$(grep -n 'set_fail_closed_read_only "startup-before-role-decision"' "${script}" | tail -1 | cut -d: -f1)
    gate_line=$(grep -n 'touch "${SYNCER_HA_READY_FILE}"' "${script}" | tail -1 | cut -d: -f1)
    When call test "${gate_line}" -gt "${fence_line}"
    The status should be success
  End

  It "re-arms the HA startup gate for every mariadbd process restart"
    script="$(chart_path)/scripts/replication-entrypoint.sh"
    clear_line=$(grep -n '^rm -f "${SYNCER_HA_READY_FILE}"' "${script}" | head -1 | cut -d: -f1)
    lifecycle_line=$(grep -n '^if \[ ! -f "${LIFECYCLE_MARKER}" \]' "${script}" | head -1 | cut -d: -f1)
    When call test "${clear_line}" -lt "${lifecycle_line}"
    The status should be success
  End
End
