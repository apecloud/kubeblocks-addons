# shellcheck shell=sh

Describe "galera-roleprobe.sh"
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

  It "publishes primary only when the data-plane watcher marks the node primary"
    printf "primary" > "${DATA_DIR}/.galera-role"

    When run sh ../scripts/galera-roleprobe.sh
    The status should be success
    The output should eq "primary"
  End

  It "refuses a stale primary marker left by a dead writer"
    # mariadb container died; kbagent keeps probing the PV-resident marker.
    printf "primary" > "${DATA_DIR}/.galera-role"
    touch -t 202001010000 "${DATA_DIR}/.galera-role"

    When run sh ../scripts/galera-roleprobe.sh
    The status should be failure
    The stderr should include "stale"
  End

  It "refuses a marker with a future mtime (clock skew is anomalous, not fresh)"
    printf "primary" > "${DATA_DIR}/.galera-role"
    touch -t 209901010000 "${DATA_DIR}/.galera-role"

    When run sh ../scripts/galera-roleprobe.sh
    The status should be failure
    The stderr should include "stale"
  End

  It "does not publish secondary while the Galera member is still joining"
    printf "secondary" > "${DATA_DIR}/.galera-role"

    When run sh ../scripts/galera-roleprobe.sh
    The status should be failure
    The stderr should include "not rollout-ready"
  End

  It "does not publish a role before the watcher has observed Galera state"
    When run sh ../scripts/galera-roleprobe.sh
    The status should be failure
    The stderr should include "role not ready"
  End
End
