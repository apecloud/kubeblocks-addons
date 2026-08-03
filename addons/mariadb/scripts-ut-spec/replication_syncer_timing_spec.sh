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
End
