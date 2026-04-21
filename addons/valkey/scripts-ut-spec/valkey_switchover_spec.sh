# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_switchover_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Switchover Bash Script Tests"
  Include $common_library_file
  Include ../scripts/switchover.sh

  init() {
    ut_mode="true"
    export SERVICE_PORT="6379"
    export COMPONENT_REPLICAS="3"
    export KB_SWITCHOVER_ROLE="primary"
  }
  BeforeAll "init"

  cleanup() {
    rm -f "${common_library_file}"
    unset SERVICE_PORT
    unset COMPONENT_REPLICAS
    unset KB_SWITCHOVER_ROLE
  }
  AfterAll "cleanup"

  Describe "get_role()"
    Context "when valkey-cli returns master"
      setup() {
        export VALKEY_DEFAULT_PASSWORD=""
      }
      Before "setup"

      It "returns 'master'"
        valkey-cli() {
          printf "# Replication\r\nrole:master\r\nconnected_slaves:1\r\n"
        }
        When call get_role "valkey-0.headless.default.svc.cluster.local"
        The status should be success
        The stdout should eq "master"
      End
    End

    Context "when valkey-cli returns slave"
      It "returns 'slave'"
        valkey-cli() {
          printf "# Replication\r\nrole:slave\r\nmaster_host:valkey-0\r\n"
        }
        When call get_role "valkey-1.headless.default.svc.cluster.local"
        The status should be success
        The stdout should eq "slave"
      End
    End

    Context "when connection fails"
      It "returns empty string (exits 0 due to pipeline)"
        valkey-cli() {
          return 1
        }
        When call get_role "unreachable-host"
        The status should be success
        The stdout should eq ""
      End
    End
  End

  Describe "promote_replica()"
    Context "when REPLICAOF NO ONE succeeds"
      It "returns success"
        valkey-cli() {
          echo "OK"
        }
        When call promote_replica "valkey-1.headless.default.svc.cluster.local"
        The status should be success
        The stdout should include "Promoting"
      End
    End

    Context "when REPLICAOF NO ONE returns unexpected response"
      It "returns failure"
        valkey-cli() {
          echo "ERR This instance has cluster support disabled"
        }
        When call promote_replica "valkey-1.headless.default.svc.cluster.local"
        The status should be failure
        The stdout should include "Promoting"
        The stderr should include "returned unexpected response"
      End
    End
  End

  Describe "repoint_replicas()"
    setup() {
      export VALKEY_POD_FQDN_LIST="valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local,valkey-2.headless.default.svc.cluster.local"
      export SERVICE_PORT="6379"
    }
    Before "setup"

    teardown() {
      unset VALKEY_POD_FQDN_LIST
    }
    After "teardown"

    Context "when new primary is valkey-1"
      It "repoints valkey-0 and valkey-2, skips valkey-1"
        repointed=""
        call_func_with_retry() {
          # args: retries delay func fqdn new_primary port
          repointed="${repointed}${4},"
        }
        When call repoint_replicas "valkey-1.headless.default.svc.cluster.local"
        The status should be success
        The variable repointed should include "valkey-0"
        The variable repointed should include "valkey-2"
        The variable repointed should not include "valkey-1"
      End
    End
  End

  Describe "repoint_one()"
    Context "when REPLICAOF returns OK"
      It "returns success"
        valkey-cli() { echo "OK"; }
        When call repoint_one "valkey-1.headless.default.svc.cluster.local" "valkey-0.headless.default.svc.cluster.local" "6379"
        The status should be success
      End
    End

    Context "when REPLICAOF returns an unexpected response"
      It "returns failure with an error message"
        valkey-cli() { echo "ERR unknown command"; }
        When call repoint_one "valkey-1.headless.default.svc.cluster.local" "valkey-0.headless.default.svc.cluster.local" "6379"
        The status should be failure
        The stderr should include "ERROR"
        The stderr should include "returned:"
      End
    End
  End

  Describe "pick_any_secondary()"
    Context "when a secondary exists"
      setup() {
        export KB_SWITCHOVER_CURRENT_FQDN="valkey-0.headless.default.svc.cluster.local"
        export VALKEY_POD_FQDN_LIST="valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local,valkey-2.headless.default.svc.cluster.local"
      }
      Before "setup"

      teardown() {
        unset KB_SWITCHOVER_CURRENT_FQDN
        unset VALKEY_POD_FQDN_LIST
      }
      After "teardown"

      It "returns the first slave found"
        get_role() {
          case "$1" in
            *"valkey-0"*) echo "master" ;;
            *"valkey-1"*) echo "slave" ;;
            *"valkey-2"*) echo "slave" ;;
          esac
        }
        When call pick_any_secondary
        The status should be success
        The stdout should include "valkey-1"
      End
    End

    Context "when no secondary is available"
      setup() {
        export KB_SWITCHOVER_CURRENT_FQDN="valkey-0.headless.default.svc.cluster.local"
        export VALKEY_POD_FQDN_LIST="valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local"
      }
      Before "setup"

      teardown() {
        unset KB_SWITCHOVER_CURRENT_FQDN
        unset VALKEY_POD_FQDN_LIST
      }
      After "teardown"

      It "returns empty string"
        get_role() {
          echo "master"
        }
        When call pick_any_secondary
        The status should be success
        The stdout should eq ""
      End
    End
  End

  Describe "execute_sentinel_failover()"
    Context "when first Sentinel accepts the failover"
      setup() {
        export VALKEY_COMPONENT_NAME="mycluster-valkey"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local,sentinel-1.headless.default.svc.cluster.local"
        export SENTINEL_SERVICE_PORT="26379"
      }
      Before "setup"

      teardown() {
        unset VALKEY_COMPONENT_NAME
        unset SENTINEL_POD_FQDN_LIST
        unset SENTINEL_SERVICE_PORT
      }
      After "teardown"

      It "returns success"
        valkey-cli() {
          echo "OK"
        }
        When call execute_sentinel_failover
        The status should be success
        The stdout should include "FAILOVER accepted"
      End
    End

    Context "when all Sentinels reject the failover"
      setup() {
        export VALKEY_COMPONENT_NAME="mycluster-valkey"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local"
        export SENTINEL_SERVICE_PORT="26379"
      }
      Before "setup"

      teardown() {
        unset VALKEY_COMPONENT_NAME
        unset SENTINEL_POD_FQDN_LIST
        unset SENTINEL_SERVICE_PORT
      }
      After "teardown"

      It "returns failure"
        valkey-cli() {
          echo "(error) ERR No such master with that name"
        }
        When call execute_sentinel_failover
        The status should be failure
        The stderr should include "all Sentinel FAILOVER attempts failed"
      End
    End
  End

  Describe "switchover_with_sentinel() — candidate role pre-check"
    setup() {
      export VALKEY_COMPONENT_NAME="mycluster-valkey"
      export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local"
      export SENTINEL_SERVICE_PORT="26379"
      export VALKEY_POD_FQDN_LIST="valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local"
      export KB_SWITCHOVER_CURRENT_FQDN="valkey-0.headless.default.svc.cluster.local"
    }
    Before "setup"

    teardown() {
      unset VALKEY_COMPONENT_NAME
      unset SENTINEL_POD_FQDN_LIST
      unset SENTINEL_SERVICE_PORT
      unset VALKEY_POD_FQDN_LIST
      unset KB_SWITCHOVER_CURRENT_FQDN
    }
    After "teardown"

    Context "when candidate is already master (idempotent — target state achieved)"
      It "returns success immediately without calling execute_sentinel_failover"
        valkey-cli() {
          printf 'role:master\n'
        }
        execute_sentinel_failover() { echo "SHOULD_NOT_BE_CALLED"; }
        When call switchover_with_sentinel "valkey-1.headless.default.svc.cluster.local"
        The status should be success
        The stderr should include "already master"
        The stderr should include "idempotent"
        The stdout should not include "SHOULD_NOT_BE_CALLED"
      End
    End

    Context "when wait_sentinel_sees_priority times out — priorities are restored before aborting"
      It "restores all replica priorities to 100 and returns failure without calling execute_sentinel_failover"
        get_role() { echo "slave"; }
        set_replica_priority() { echo "SET_PRIO:${1}:${2}"; return 0; }
        wait_sentinel_sees_priority() { return 1; }
        execute_sentinel_failover() { echo "SHOULD_NOT_BE_CALLED"; }
        When call switchover_with_sentinel "valkey-1.headless.default.svc.cluster.local"
        The status should be failure
        The stdout should include "SET_PRIO:valkey-0.headless.default.svc.cluster.local:100"
        The stdout should include "SET_PRIO:valkey-1.headless.default.svc.cluster.local:100"
        The stdout should not include "SHOULD_NOT_BE_CALLED"
      End
    End

    Context "when candidate role is unknown (get_role returns empty — transient network issue)"
      It "logs a warning and proceeds to call Sentinel (does not abort)"
        get_role() { echo ""; }
        set_replica_priority() { return 0; }
        wait_sentinel_sees_priority() { return 0; }
        execute_sentinel_failover() { echo "OK"; return 0; }
        wait_for_new_master() { return 0; }
        When call switchover_with_sentinel "valkey-1.headless.default.svc.cluster.local"
        The status should be success
        The stdout should include "Biasing"
        The stderr should include "WARNING"
        The stderr should include "after retries — proceeding without role pre-check"
      End
    End

    Context "when candidate role is 'slave' (normal path)"
      It "proceeds to call Sentinel without warnings"
        get_role() { echo "slave"; }
        set_replica_priority() { return 0; }
        wait_sentinel_sees_priority() { return 0; }
        execute_sentinel_failover() { echo "OK"; return 0; }
        wait_for_new_master() { return 0; }
        When call switchover_with_sentinel "valkey-1.headless.default.svc.cluster.local"
        The status should be success
        The stdout should include "Biasing"
        The stderr should eq ""
      End
    End

    Context "when candidate role is an unexpected value (e.g. 'connecting') — neither master nor slave"
      It "aborts with an ERROR and does not call execute_sentinel_failover"
        get_role() { echo "connecting"; }
        execute_sentinel_failover() { echo "SHOULD_NOT_BE_CALLED"; }
        When call switchover_with_sentinel "valkey-1.headless.default.svc.cluster.local"
        The status should be failure
        The stderr should include "ERROR"
        The stderr should include "expected 'slave'"
        The stdout should not include "SHOULD_NOT_BE_CALLED"
      End
    End

    Context "when FAILOVER accepted but wrong candidate becomes master — priority restore deferred until after confirmation"
      It "restores priorities only after wait_for_new_master (not before), and returns failure"
        restore_order=""
        get_role() { echo "slave"; }
        set_replica_priority() {
          # Record calls: tag 'during' only if wait_for_new_master has NOT run yet
          if [ -z "${wfnm_done:-}" ]; then
            restore_order="${restore_order}bias:"
          else
            restore_order="${restore_order}restore:"
          fi
          echo "SET_PRIO:${1}:${2}"
          return 0
        }
        wait_sentinel_sees_priority() { return 0; }
        execute_sentinel_failover() { echo "OK"; return 0; }
        wait_for_new_master() {
          wfnm_done=1
          restore_order="${restore_order}wfnm:"
          return 1
        }
        When call switchover_with_sentinel "valkey-1.headless.default.svc.cluster.local"
        The status should be failure
        The stdout should include "Biasing"
        # wfnm must appear before 'restore' in the ordering string
        The variable restore_order should include "wfnm:restore:"
        The variable restore_order should not include "restore:wfnm:"
      End
    End
  End

  Describe "wait_sentinel_sees_priority()"
    setup() {
      export VALKEY_COMPONENT_NAME="mycluster-valkey"
      export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local"
      export SENTINEL_SERVICE_PORT="26379"
    }
    Before "setup"

    teardown() {
      unset VALKEY_COMPONENT_NAME
      unset SENTINEL_POD_FQDN_LIST
      unset SENTINEL_SERVICE_PORT
    }
    After "teardown"

    Context "when Sentinel immediately reflects the expected priority"
      It "returns success with a confirmation message"
        valkey-cli() {
          # Simulate SENTINEL REPLICAS output (flat, without array-index prefixes)
          printf 'name\nvalkey-1.headless.default.svc.cluster.local:6379\nslave-priority\n1\n'
        }
        When call wait_sentinel_sees_priority "valkey-1.headless.default.svc.cluster.local" "1"
        The status should be success
        The stdout should include "Sentinel(s) confirmed"
        The stderr should eq ""
      End
    End

    Context "when Sentinel does not reflect the priority within the deadline"
      It "returns failure with an ERROR (aborts to prevent wrong-node promotion)"
        valkey-cli() {
          printf 'name\nvalkey-1.headless.default.svc.cluster.local:6379\nslave-priority\n100\n'
        }
        When call wait_sentinel_sees_priority "valkey-1.headless.default.svc.cluster.local" "1"
        The status should be failure
        The stderr should include "ERROR"
        The stderr should include "aborting targeted switchover"
      End
    End

    Context "when Sentinel output contains multiple replicas and the candidate is not first"
      It "correctly identifies the candidate and returns success"
        valkey-cli() {
          # Two replicas; candidate valkey-1 is listed second
          printf 'name\nvalkey-2.headless.default.svc.cluster.local:6379\nslave-priority\n100\nname\nvalkey-1.headless.default.svc.cluster.local:6379\nslave-priority\n1\n'
        }
        When call wait_sentinel_sees_priority "valkey-1.headless.default.svc.cluster.local" "1"
        The status should be success
        The stdout should include "Sentinel(s) confirmed"
      End
    End

    Context "when two Sentinels and both have updated the priority cache (all-match)"
      setup_two_sentinels() {
        export VALKEY_COMPONENT_NAME="mycluster-valkey"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local,sentinel-1.headless.default.svc.cluster.local"
        export SENTINEL_SERVICE_PORT="26379"
      }
      teardown_two_sentinels() {
        unset VALKEY_COMPONENT_NAME
        unset SENTINEL_POD_FQDN_LIST
        unset SENTINEL_SERVICE_PORT
      }
      Before "setup_two_sentinels"
      After "teardown_two_sentinels"

      It "returns success only when all sentinels confirm"
        valkey-cli() {
          # Both sentinel-0 and sentinel-1 return priority=1 for valkey-1
          printf 'name\nvalkey-1.headless.default.svc.cluster.local:6379\nslave-priority\n1\n'
        }
        When call wait_sentinel_sees_priority "valkey-1.headless.default.svc.cluster.local" "1"
        The status should be success
        The stdout should include "All 2 Sentinel(s) confirmed"
      End
    End

    Context "when two Sentinels and only one has updated the priority cache (cross-sentinel stale)"
      setup_two_sentinels_stale() {
        export VALKEY_COMPONENT_NAME="mycluster-valkey"
        export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local,sentinel-1.headless.default.svc.cluster.local"
        export SENTINEL_SERVICE_PORT="26379"
      }
      teardown_two_sentinels_stale() {
        unset VALKEY_COMPONENT_NAME
        unset SENTINEL_POD_FQDN_LIST
        unset SENTINEL_SERVICE_PORT
      }
      Before "setup_two_sentinels_stale"
      After "teardown_two_sentinels_stale"

      It "returns failure — does not return success on first-match (regression guard)"
        valkey-cli() {
          local args="$*"
          # sentinel-1 has updated cache (priority=1), sentinel-0 is still stale (priority=100)
          case "${args}" in
            *"sentinel-0"*) printf 'name\nvalkey-1.headless.default.svc.cluster.local:6379\nslave-priority\n100\n' ;;
            *"sentinel-1"*) printf 'name\nvalkey-1.headless.default.svc.cluster.local:6379\nslave-priority\n1\n' ;;
          esac
        }
        When call wait_sentinel_sees_priority "valkey-1.headless.default.svc.cluster.local" "1"
        The status should be failure
        The stderr should include "ERROR"
        The stderr should include "aborting targeted switchover"
      End
    End
  End

  Describe "set_replica_priority()"
    It "logs a warning and returns failure when CONFIG SET returns unexpected output"
      valkey-cli() {
        echo "(error) ERR"
      }
      When call set_replica_priority "valkey-1.headless.default.svc.cluster.local" "1"
      The status should be failure
      The stderr should include "WARNING"
    End

    It "succeeds silently when CONFIG SET returns OK"
      valkey-cli() {
        echo "OK"
      }
      When call set_replica_priority "valkey-1.headless.default.svc.cluster.local" "100"
      The status should be success
      The stderr should eq ""
    End
  End

  Describe "wait_until_master()"
    Context "when the target becomes master before max_wait"
      It "returns success"
        get_role() { echo "master"; }
        When call wait_until_master "valkey-1.headless.default.svc.cluster.local" 10
        The status should be success
      End
    End

    Context "when the target never becomes master (max_wait=0 to exit immediately)"
      It "returns failure with a WARNING"
        get_role() { echo "slave"; }
        When call wait_until_master "valkey-1.headless.default.svc.cluster.local" 0
        The status should be failure
        The stderr should include "WARNING"
        The stderr should include "did not confirm master role"
      End
    End
  End

  Describe "wait_for_new_master()"
    setup() {
      export VALKEY_POD_FQDN_LIST="valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local,valkey-2.headless.default.svc.cluster.local"
    }
    Before "setup"

    teardown() {
      unset VALKEY_POD_FQDN_LIST
    }
    After "teardown"

    Context "when expected candidate becomes master before timeout"
      It "returns success and prints confirmation"
        get_role() {
          case "$1" in
            *"valkey-1"*) echo "master" ;;
            *) echo "slave" ;;
          esac
        }
        When call wait_for_new_master "valkey-1.headless.default.svc.cluster.local" ""
        The status should be success
        The stdout should include "New primary confirmed"
        The stdout should include "valkey-1"
      End
    End

    Context "when no new master appears within max_wait (simulated via small limit)"
      It "returns failure with a WARNING"
        get_role() { echo "slave"; }
        # Override max_wait to 0 so the loop exits immediately
        wait_for_new_master() {
          local expected_fqdn="${1}" exclude_fqdn="${2}"
          local max_wait=0 elapsed=0
          while [ "${elapsed}" -lt "${max_wait}" ]; do
            elapsed=$((elapsed + 3))
          done
          echo "WARNING: ${expected_fqdn} did not confirm master role within ${max_wait}s" >&2
          return 1
        }
        When call wait_for_new_master "valkey-1.headless.default.svc.cluster.local" ""
        The status should be failure
        The stderr should include "WARNING"
      End
    End

    Context "when exclude_fqdn matches the current master (old master still reporting master)"
      It "skips the excluded FQDN and returns success when a different node becomes master"
        get_role() {
          case "$1" in
            *"valkey-0"*) echo "master" ;;
            *"valkey-1"*) echo "master" ;;
            *) echo "slave" ;;
          esac
        }
        # valkey-0 is old master (excluded), valkey-1 is new master
        When call wait_for_new_master "valkey-1.headless.default.svc.cluster.local" "valkey-0.headless.default.svc.cluster.local"
        The status should be success
        The stdout should include "valkey-1"
      End
    End

    Context "when expected_fqdn is empty — any new master is acceptable"
      It "returns success as soon as any non-excluded node reports master"
        get_role() {
          case "$1" in
            *"valkey-2"*) echo "master" ;;
            *) echo "slave" ;;
          esac
        }
        When call wait_for_new_master "" "valkey-0.headless.default.svc.cluster.local"
        The status should be success
        The stdout should include "New primary confirmed"
      End
    End
  End

  Describe "switchover_with_sentinel() — success path restore ordering"
    setup() {
      export VALKEY_COMPONENT_NAME="mycluster-valkey"
      export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local"
      export SENTINEL_SERVICE_PORT="26379"
      export VALKEY_POD_FQDN_LIST="valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local"
      export KB_SWITCHOVER_CURRENT_FQDN="valkey-0.headless.default.svc.cluster.local"
    }
    Before "setup"

    teardown() {
      unset VALKEY_COMPONENT_NAME
      unset SENTINEL_POD_FQDN_LIST
      unset SENTINEL_SERVICE_PORT
      unset VALKEY_POD_FQDN_LIST
      unset KB_SWITCHOVER_CURRENT_FQDN
    }
    After "teardown"

    Context "when FAILOVER accepted and correct candidate becomes master — priorities restored after wait_for_new_master succeeds"
      It "restores priorities only after wait_for_new_master (not before), and returns success"
        restore_order=""
        get_role() { echo "slave"; }
        set_replica_priority() {
          if [ -z "${wfnm_done:-}" ]; then
            restore_order="${restore_order}bias:"
          else
            restore_order="${restore_order}restore:"
          fi
          echo "SET_PRIO:${1}:${2}"
          return 0
        }
        wait_sentinel_sees_priority() { return 0; }
        execute_sentinel_failover() { echo "OK"; return 0; }
        wait_for_new_master() {
          wfnm_done=1
          restore_order="${restore_order}wfnm:"
          return 0
        }
        When call switchover_with_sentinel "valkey-1.headless.default.svc.cluster.local"
        The status should be success
        The stdout should include "Biasing"
        # wfnm must appear before 'restore' in the ordering string
        The variable restore_order should include "wfnm:restore:"
        The variable restore_order should not include "restore:wfnm:"
      End
    End

    Context "when execute_sentinel_failover fails — priorities restored before returning failure"
      It "restores all replica priorities to 100 and returns failure"
        get_role() { echo "slave"; }
        set_replica_priority() { echo "SET_PRIO:${1}:${2}"; return 0; }
        wait_sentinel_sees_priority() { return 0; }
        execute_sentinel_failover() { return 1; }
        wait_for_new_master() { echo "SHOULD_NOT_BE_CALLED"; return 0; }
        When call switchover_with_sentinel "valkey-1.headless.default.svc.cluster.local"
        The status should be failure
        The stdout should include "SET_PRIO:valkey-0.headless.default.svc.cluster.local:100"
        The stdout should include "SET_PRIO:valkey-1.headless.default.svc.cluster.local:100"
        The stdout should not include "SHOULD_NOT_BE_CALLED"
      End
    End
  End

  Describe "switchover_with_sentinel() — no-candidate path"
    setup() {
      export VALKEY_COMPONENT_NAME="mycluster-valkey"
      export SENTINEL_POD_FQDN_LIST="sentinel-0.headless.default.svc.cluster.local"
      export SENTINEL_SERVICE_PORT="26379"
      export VALKEY_POD_FQDN_LIST="valkey-0.headless.default.svc.cluster.local,valkey-1.headless.default.svc.cluster.local"
      export KB_SWITCHOVER_CURRENT_FQDN="valkey-0.headless.default.svc.cluster.local"
    }
    Before "setup"

    teardown() {
      unset VALKEY_COMPONENT_NAME
      unset SENTINEL_POD_FQDN_LIST
      unset SENTINEL_SERVICE_PORT
      unset VALKEY_POD_FQDN_LIST
      unset KB_SWITCHOVER_CURRENT_FQDN
    }
    After "teardown"

    Context "when no candidate specified — skips priority bias and delegates directly to Sentinel"
      It "calls execute_sentinel_failover without setting any replica priority"
        priority_set_called=""
        set_replica_priority() { priority_set_called="yes"; return 0; }
        execute_sentinel_failover() { echo "OK"; return 0; }
        wait_for_new_master() { return 0; }
        When call switchover_with_sentinel ""
        The status should be success
        The stdout should include "OK"
        The variable priority_set_called should eq ""
      End
    End
  End
End
