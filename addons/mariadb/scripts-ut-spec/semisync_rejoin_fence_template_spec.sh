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

  It "declares an internal local admin before fencing user-facing root"
    When call template_contains 'MARIADB_INTERNAL_ROOT_USER="${MARIADB_INTERNAL_ROOT_USER:-kb_internal_root}"'
    The status should be success
    The output should include "MARIADB_INTERNAL_ROOT_USER"
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

  It "locks local root after putting a replica into read-only"
    When call function_contains "set_replica_read_only" "lock_local_root_writes \"replica-read-only\""
    The status should be success
  End

  It "unlocks local root before publishing a primary as writable"
    When call function_contains "set_primary_read_write" "unlock_local_root_writes \"primary-read-write\""
    The status should be success
  End

  It "keeps unresolved startup locally fenced"
    When call template_contains "lock_local_root_writes \"startup-before-role-decision\""
    The status should be success
    The output should include "startup-before-role-decision"
  End

  It "keeps unresolved wait-loop roles locally fenced"
    When call template_contains "lock_local_root_writes \"wait-primary-loop-entry\""
    The status should be success
    The output should include "wait-primary-loop-entry"
  End

  It "keeps no-primary paths locally fenced"
    When call function_contains "block_existing_datadir_self_election_without_primary" "lock_local_root_writes \"no-primary-existing-datadir\""
    The status should be success
  End

  It "keeps GTID divergence paths locally fenced"
    When call function_contains "fail_closed_for_gtid_divergence" "lock_local_root_writes \"gtid-divergence\""
    The status should be success
  End

  It "uses the internal admin for preStop SQL so root can stay fenced"
    When call template_contains "mariadb -u\"\${INTERNAL_ROOT_USER}\" -p\"\${MARIADB_ROOT_PASSWORD}\""
    The status should be success
    The output should include "INTERNAL_ROOT_USER"
  End
End
