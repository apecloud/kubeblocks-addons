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

  It "does not close on a stale synced marker left by a dead writer"
    # Both markers present and role=primary, but the mariadb container that
    # writes them has died — the marker mtime is old.
    printf "primary" > "${DATA_DIR}/.galera-role"
    touch "${DATA_DIR}/.galera-synced"
    touch -t 202001010000 "${DATA_DIR}/.galera-synced"

    When run sh ../scripts/galera-member-join.sh
    The status should be failure
    The error should include "phase: synced-marker-stale"
    The error should include "next-retry-safe: yes"
  End

  It "fails closed (operator-attention) on an empty staleness threshold"
    printf "primary" > "${DATA_DIR}/.galera-role"
    touch "${DATA_DIR}/.galera-synced"
    export GALERA_ROLE_MAX_STALE_SECONDS=""

    When run sh ../scripts/galera-member-join.sh
    The status should be failure
    The error should include "phase: misconfigured-stale-threshold"
    The error should include "next-retry-safe: no"
  End

  Parameters
    "abc"
    "-5"
    "0"
  End
  It "fails closed (operator-attention) on a non-positive-integer staleness threshold (value=[$1])"
    printf "primary" > "${DATA_DIR}/.galera-role"
    touch "${DATA_DIR}/.galera-synced"
    export GALERA_ROLE_MAX_STALE_SECONDS="$1"

    When run sh ../scripts/galera-member-join.sh
    The status should be failure
    The error should include "phase: misconfigured-stale-threshold"
    The error should include "next-retry-safe: no"
  End
End
