# shellcheck shell=sh

Describe "galera-member-join.sh"
  setup() {
    TEST_DIR=$(mktemp -d)
    export DATA_DIR="${TEST_DIR}/data"
    mkdir -p "${DATA_DIR}"
  }
  BeforeEach "setup"

  cleanup() {
    rm -rf "${TEST_DIR}"
    unset DATA_DIR
  }
  AfterEach "cleanup"

  It "closes only when synced marker and primary role are both current"
    touch "${DATA_DIR}/.galera-synced"
    printf "primary" > "${DATA_DIR}/.galera-role"

    When run sh ../scripts/galera-member-join.sh
    The status should be success
    The output should include "role=primary"
  End

  It "defers when the synced marker is stale and role is no longer primary"
    touch "${DATA_DIR}/.galera-synced"
    printf "secondary" > "${DATA_DIR}/.galera-role"

    When run sh ../scripts/galera-member-join.sh
    The status should be failure
    The error should include "phase: synced-marker-stale-or-role-not-primary"
    The error should include "next-retry-safe: yes"
  End
End
