# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "promote_standby_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "PostgreSQL promote standby script tests"

  Include ../scripts/promote_standby.sh

  Describe "require_force()"
    It "rejects missing split-brain acknowledgement"
      unset force
      When run require_force
      The status should be failure
      The output should include "force=true is required"
    End

    It "accepts force=true"
      force="true"
      When run require_force
      The status should be success
    End
  End

  Describe "require_standby_mode()"
    It "rejects a non-standby cluster"
      PG_MODE="primary"
      When run require_standby_mode
      The status should be failure
      The output should include "refusing DR standby promotion"
    End

    It "accepts standby mode"
      PG_MODE="standby"
      When run require_standby_mode
      The status should be success
    End
  End

  Describe "promote_standby()"
    It "does not patch Patroni from a non-standby-leader pod"
      force="true"
      PG_MODE="standby"
      CURRENT_POD_IP="127.0.0.1"
      curl() {
        case "$*" in
          *"/standby-leader"*) printf '503' ;;
          *) echo "unexpected curl: $*" ; return 1 ;;
        esac
      }
      When run promote_standby
      The status should be success
      The output should include "not Patroni standby leader"
    End
  End
End
