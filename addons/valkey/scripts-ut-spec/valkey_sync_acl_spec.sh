# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_sync_acl_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Sync-ACL Bash Script Tests"
  Include $common_library_file
  Include ../scripts/sync-acl.sh

  init() {
    ut_mode="true"
    export SERVICE_PORT="6379"
  }
  BeforeAll "init"

  cleanup() {
    rm -f "${common_library_file}"
    unset SERVICE_PORT
  }
  AfterAll "cleanup"

  Describe "find_primary_fqdn()"
    Context "when one pod reports role:master"
      setup() {
        export VALKEY_POD_NAME_LIST="valkey-0,valkey-1,valkey-2"
        export VALKEY_POD_FQDN_LIST="valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local,valkey-2.headless.default.svc.cluster.local"
      }
      Before "setup"

      teardown() {
        unset VALKEY_POD_NAME_LIST
        unset VALKEY_POD_FQDN_LIST
      }
      After "teardown"

      It "returns the FQDN of the master pod"
        valkey-cli() {
          # Only valkey-1 is master
          case "$@" in
            *"valkey-0"*) printf "role:slave\r\n" ;;
            *"valkey-1"*) printf "role:master\r\n" ;;
            *"valkey-2"*) printf "role:slave\r\n" ;;
          esac
        }
        When call find_primary_fqdn
        The status should be success
        The stdout should eq "valkey-1.headless.default.svc.cluster.local"
      End

      It "rejects an ambiguous view with two locally reported masters"
        valkey-cli() {
          case "$@" in
            *"valkey-2"*) printf "role:slave\r\n" ;;
            *) printf "role:master\r\n" ;;
          esac
        }
        When call find_primary_fqdn
        The status should be failure
        The stdout should eq ""
        The stderr should include "2 pods reported role:master"
      End
    End

    Context "when no pod reports role:master"
      setup() {
        export VALKEY_POD_NAME_LIST="valkey-2,valkey-0,valkey-1"
        export VALKEY_POD_FQDN_LIST="valkey-2.headless.default.svc.cluster.local,valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local"
      }
      Before "setup"

      teardown() {
        unset VALKEY_POD_NAME_LIST
        unset VALKEY_POD_FQDN_LIST
      }
      After "teardown"

      It "fails closed instead of guessing a lexicographic ACL source"
        valkey-cli() {
          printf "role:slave\r\n"
        }
        When call find_primary_fqdn
        The status should be failure
        The stdout should eq ""
        The stderr should include "refusing an ambiguous ACL source"
      End
    End
  End

  Describe "sync_acl_to_replica()"
    Context "when ACL LIST returns valid rules"
      It "syncs non-default ACL users to the replica and saves"
        valkey-cli() {
          case "$@" in
            *"ACL LIST"*)
              printf "user default on nopass ~* &* +@all\nuser app on >apppass ~* +@all\n"
              ;;
            *"ACL SETUSER"*)
              echo "OK"
              ;;
            *"ACL SAVE"*)
              echo "OK"
              ;;
          esac
        }
        When call sync_acl_to_replica \
          "valkey-0.headless.default.svc.cluster.local" \
          "valkey-1.headless.default.svc.cluster.local"
        The status should be success
        The stdout should include "ACL SETUSER app"
        The stdout should include "ACL sync complete"
      End

      It "does not print ACL rule payloads (password material) to logs"
        valkey-cli() {
          case "$@" in
            *"ACL LIST"*)
              printf "user default on nopass ~* &* +@all\nuser app on >apppass ~* +@all\n"
              ;;
            *"ACL SETUSER"*)
              echo "OK"
              ;;
            *"ACL SAVE"*)
              echo "OK"
              ;;
          esac
        }
        When call sync_acl_to_replica \
          "valkey-0.headless.default.svc.cluster.local" \
          "valkey-1.headless.default.svc.cluster.local"
        The status should be success
        The stdout should not include "apppass"
        The stderr should not include "apppass"
      End
    End

    Context "when ACL LIST fails"
      It "returns failure and logs an error"
        valkey-cli() {
          case "$@" in
            *"ACL LIST"*)
              echo "(error) ERR unknown command"
              ;;
          esac
        }
        When call sync_acl_to_replica \
          "valkey-0.headless.default.svc.cluster.local" \
          "valkey-1.headless.default.svc.cluster.local"
        The status should be failure
        The stdout should include "Syncing ACL"
        The stderr should include "ERROR"
      End

      It "rejects an empty successful ACL LIST reply"
        valkey-cli() {
          case "$@" in
            *"ACL LIST"*) printf '' ;;
          esac
        }
        When call sync_acl_to_replica source target
        The status should be failure
        The stdout should include "Syncing ACL"
        The stderr should include "returned an empty reply"
        The variable SYNC_ACL_RETRY_SAFE should eq "no"
      End

      It "rejects malformed ACL LIST records before replay"
        valkey-cli() {
          case "$@" in
            *"ACL LIST"*) echo "not-a-user-rule" ;;
          esac
        }
        When call sync_acl_to_replica source target
        The status should be failure
        The stdout should include "Syncing ACL"
        The stderr should include "contains a malformed rule"
        The variable SYNC_ACL_RETRY_SAFE should eq "no"
      End
    End

    Context "when only default user exists"
      It "skips the default user and saves"
        valkey-cli() {
          case "$@" in
            *"ACL LIST"*)
              echo "user default on nopass ~* &* +@all"
              ;;
            *"ACL SAVE"*)
              echo "OK"
              ;;
          esac
        }
        When call sync_acl_to_replica \
          "valkey-0.headless.default.svc.cluster.local" \
          "valkey-1.headless.default.svc.cluster.local"
        The status should be success
        The stdout should not include "ACL SETUSER default"
        The stdout should include "ACL sync complete"
      End
    End

    Context "when ACL SAVE fails"
      It "returns failure when ACL SAVE fails"
        valkey-cli() {
          case "$@" in
            *"ACL LIST"*)
              echo "user default on nopass ~* &* +@all"
              ;;
            *"ACL SAVE"*)
              echo "(error) ERR ACL SAVE is not allowed when aclfile is not configured"
              ;;
          esac
        }
        When call sync_acl_to_replica \
          "valkey-0.headless.default.svc.cluster.local" \
          "valkey-1.headless.default.svc.cluster.local"
        The status should be failure
        The stdout should include "Syncing ACL"
        The stderr should include "ACL SAVE returned non-OK reply"
      End
    End

    Context "when ACL SETUSER fails for some users"
      It "returns failure with partial sync error count"
        valkey-cli() {
          case "$@" in
            *"ACL LIST"*)
              printf "user default on nopass ~* &* +@all\nuser app on >apppass ~* +@all\nuser monitor on >monpass ~* +@read\n"
              ;;
            *"ACL SETUSER app"*)
              echo "OK"
              ;;
            *"ACL SETUSER monitor"*)
              echo "ERR unknown command"
              ;;
            *"ACL SAVE"*)
              echo "OK"
              ;;
          esac
        }
        When call sync_acl_to_replica \
          "valkey-0.headless.default.svc.cluster.local" \
          "valkey-1.headless.default.svc.cluster.local"
        The status should be failure
        The stdout should include "Syncing ACL"
        The stderr should include "ACL SETUSER for monitor returned non-OK reply"
        The stderr should include "ERROR: ACL sync completed with 1 failure(s)"
      End

      It "rejects an empty SETUSER reply"
        valkey-cli() {
          case "$@" in
            *"ACL LIST"*) echo "user app on >apppass ~* +@all" ;;
            *"ACL SETUSER"*) printf '' ;;
            *"ACL SAVE"*) echo "OK" ;;
          esac
        }
        When call sync_acl_to_replica source target
        The status should be failure
        The stdout should include "Syncing ACL"
        The stderr should include "returned non-OK reply"
      End

      It "rejects an unexpected successful SETUSER reply"
        valkey-cli() {
          case "$@" in
            *"ACL LIST"*) echo "user app on >apppass ~* +@all" ;;
            *"ACL SETUSER"*) echo "QUEUED" ;;
            *"ACL SAVE"*) echo "OK" ;;
          esac
        }
        When call sync_acl_to_replica source target
        The status should be failure
        The stdout should include "Syncing ACL"
        The stderr should include "returned non-OK reply: QUEUED"
      End

      It "classifies a nonzero SETUSER transport result as retryable"
        valkey-cli() {
          case "$@" in
            *"ACL LIST"*) echo "user app on >apppass ~* +@all" ;;
            *"ACL SETUSER"*) return 124 ;;
            *"ACL SAVE"*) echo "OK" ;;
          esac
        }
        When call sync_acl_to_replica source target
        The status should be failure
        The stdout should include "Syncing ACL"
        The stderr should include "failed with rc=124"
        The variable SYNC_ACL_RETRY_SAFE should eq "yes"
      End
    End
  End

  Describe "memberJoin action contract"
    sync_script="../scripts/sync-acl.sh"
    cmpd_file="../templates/cmpd.yaml"

    It "fails closed when the action-time member identity is missing"
      missing_identity_contract() {
        ! grep -F "nothing to sync" "${sync_script}" >/dev/null &&
          grep -F "KB_JOIN_MEMBER_POD_NAME and KB_JOIN_MEMBER_POD_FQDN are both required" \
            "${sync_script}" >/dev/null
      }
      When call missing_identity_contract
      The status should be success
    End

    It "bounds every production Valkey CLI call"
      When call grep -F "timeout \"\${ACTION_CLIENT_TIMEOUT_SECONDS}\" \"\$@\"" "${sync_script}"
      The status should be success
      The stdout should include "timeout"
    End

    It "declares a truthful action timeout and retry policy"
      member_join_action_contract() {
        awk '
          /^    memberJoin:/ { in_action=1; next }
          in_action && /^      timeoutSeconds: 50$/ { timeout=1 }
          in_action && /^      retryPolicy:/ { retry=1 }
          in_action && /^        maxRetries: 10$/ { retries=1 }
          in_action && /^        retryInterval: 3$/ { interval=1 }
          in_action && /^    memberLeave:/ {
            exit !(timeout && retry && retries && interval)
          }
          END {
            if (!(timeout && retry && retries && interval)) exit 1
          }
        ' "${cmpd_file}"
      }
      When call member_join_action_contract
      The status should be success
    End
  End
End
