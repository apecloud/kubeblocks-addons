# shellcheck shell=bash

Describe "MySQL Orchestrator switchover fail-close contract"
  setup() {
    ORCHESTRATOR_CLIENT=$(mktemp)
    export ORCHESTRATOR_CLIENT
    export KB_SWITCHOVER_ROLE=primary
    export KB_SWITCHOVER_CURRENT_NAME=mysql-0
    export KB_SWITCHOVER_CANDIDATE_NAME=mysql-1
    export ORC_MASTER_RC=0
    export ORC_SWITCH_RC=0

    cat >"$ORCHESTRATOR_CLIENT" <<'MOCK'
#!/bin/bash
case "$*" in
  *"which-cluster-master"*)
    if [ "${ORC_MASTER_RC:-0}" -ne 0 ]; then
      printf 'orchestrator unavailable\n' >&2
      exit "$ORC_MASTER_RC"
    fi
    printf 'mysql-0:3306\n'
    ;;
  *"which-cluster-instances"*)
    printf 'mysql-0:3306\nmysql-1:3306\n'
    ;;
  *"graceful-master-takeover-auto"*)
    if [ "${ORC_SWITCH_RC:-0}" -ne 0 ]; then
      printf 'takeover failed\n' >&2
      exit "$ORC_SWITCH_RC"
    fi
    printf 'takeover accepted\n'
    ;;
  *)
    printf 'unexpected command: %s\n' "$*" >&2
    exit 2
    ;;
esac
MOCK
    chmod +x "$ORCHESTRATOR_CLIENT"
  }

  cleanup() {
    rm -f "$ORCHESTRATOR_CLIENT"
  }

  BeforeEach "setup"
  AfterEach "cleanup"

  It "fails when the current master cannot be read"
    ORC_MASTER_RC=7
    export ORC_MASTER_RC

    When run bash ../scripts/orc-switchover.sh
    The status should be failure
    The stderr should include "Could not determine current master"
    The stderr should include "rc=7"
  End

  It "fails when Orchestrator rejects the takeover"
    ORC_SWITCH_RC=9
    export ORC_SWITCH_RC

    When run bash ../scripts/orc-switchover.sh
    The status should be failure
    The stdout should include "Initiating graceful switchover"
    The stderr should include "exit code 9"
    The stderr should include "takeover failed"
  End

  It "succeeds only after Orchestrator accepts the takeover"
    When run bash ../scripts/orc-switchover.sh
    The status should be success
    The stdout should include "Initiating graceful switchover"
  End
End
