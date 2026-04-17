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
    End

    Context "when no pod reports role:master (fallback to lexicographic heuristic)"
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

      It "falls back to lexicographic minimum pod (valkey-0)"
        valkey-cli() {
          printf "role:slave\r\n"
        }
        When call find_primary_fqdn
        The status should be success
        The stdout should eq "valkey-0.headless.default.svc.cluster.local"
        The stderr should include "no pod reported role:master"
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
    End

    Context "when ACL LIST fails"
      It "returns failure and logs a warning"
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
        The stderr should include "WARNING"
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
      It "prints a warning but does not fail the sync"
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
        The status should be success
        The stdout should include "ACL sync complete"
        The stderr should include "WARNING: ACL SAVE failed"
      End
    End
  End
End
