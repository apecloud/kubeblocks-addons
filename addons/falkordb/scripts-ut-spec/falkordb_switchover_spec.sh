# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_switchover_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "FalkorDB Switchover Script Tests"
  Include ../scripts/falkordb-switchover.sh
  Include $common_library_file

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  cleanup() {
    rm -f $common_library_file
  }
  AfterAll 'cleanup'

  Describe "Environment Check Tests"
    Context "check_environment_exist()"
      It "should fail when no required variables are set"
        unset SENTINEL_POD_FQDN_LIST REDIS_POD_FQDN_LIST REDIS_COMPONENT_NAME KB_SWITCHOVER_ROLE
        export COMPONENT_REPLICAS="2"
        When call check_environment_exist
        The status should be failure
        The stderr should include "Required environment variable SENTINEL_POD_FQDN_LIST is not set"
        The stdout should equal ""
      End

      It "should succeed with all required variables"
        export SENTINEL_POD_FQDN_LIST="sentinel1,sentinel2"
        export REDIS_POD_FQDN_LIST="redis1,redis2"
        export REDIS_COMPONENT_NAME="redis"
        export KB_SWITCHOVER_ROLE="primary"
        export COMPONENT_REPLICAS="2"
        When call check_environment_exist
        The status should be success
        The stdout should equal ""
        The stderr should equal ""
      End

#      It "should exit early when role is not primary"
#        export SENTINEL_POD_FQDN_LIST="sentinel1,sentinel2"
#        export REDIS_POD_FQDN_LIST="redis1,redis2"
#        export REDIS_COMPONENT_NAME="redis"
#        export KB_SWITCHOVER_ROLE="secondary"
#        When call check_environment_exist
#        The status should be success
#        The stdout should include "switchover not triggered for primary, nothing to do"
#        The stderr should equal ""
#      End
    End
  End

  Describe "FalkorDB Operation Tests"
    Context "check_redis_role()"
      setup() {
        export REDIS_DEFAULT_PASSWORD="password123"
      }
      Before 'setup'

      cleanup() {
        unset REDIS_DEFAULT_PASSWORD
      }
      After 'cleanup'

      It "should identify primary role"
        redis-cli() {
          echo "# Replication
role:master
connected_slaves:2"
        }
        When call check_redis_role "localhost" "6379"
        The status should be success
        The output should equal "primary"
        The stderr should equal ""
      End

      It "should identify secondary role"
        redis-cli() {
          echo "# Replication
role:slave
master_host:redis-master"
        }
        When call check_redis_role "localhost" "6379"
        The status should be success
        The output should equal "secondary"
        The stderr should equal ""
      End

      It "should handle redis-cli failure"
        redis-cli() {
          return 1
        }
        When call check_redis_role "localhost" "6379"
        The status should be failure
        The stderr should include "Failed to get role info from localhost"
        The output should equal ""
      End

      It "should handle empty response"
        redis-cli() {
          echo ""
        }
        When call check_redis_role "localhost" "6379"
        The status should be failure
        The output should equal "unknown"
      End
    End

    Context "run_redis_cli()"
      It "enforces a command timeout outside unit-test mode"
        ut_mode="false"
        timeout() {
          echo "TIMEOUT:$*"
        }
        When call run_redis_cli -h redis1 PING
        The status should be success
        The output should include "TIMEOUT:-k 2 5 redis-cli -h redis1 PING"
      End

      It "actually terminates a hanging redis-cli process"
        run_hanging_redis_cli_case() {
          local stub_dir
          stub_dir=$(mktemp -d)
          printf '%s\n' '#!/bin/bash' 'sleep 60' > "$stub_dir/redis-cli"
          chmod +x "$stub_dir/redis-cli"
          PATH="$stub_dir:$PATH"
          ut_mode="false"
          run_redis_cli -h redis1 PING
          local status=$?
          rm -rf "$stub_dir"
          return "$status"
        }
        When call run_hanging_redis_cli_case
        The status should be failure
      End
    End

    Context "check_redis_kernel_status()"
      setup() {
        export REDIS_POD_FQDN_LIST="redis1,redis2,redis3"
        export SERVICE_PORT="6379"
      }
      Before 'setup'

      cleanup() {
        unset REDIS_POD_FQDN_LIST
        unset SERVICE_PORT
      }
      After 'cleanup'

      It "should detect single primary correctly"
        check_redis_role() {
          case "$1" in
            "redis1") echo "primary" ;;
            *) echo "secondary" ;;
          esac
        }
        When call check_redis_kernel_status
        The status should be success
        The output should equal "redis1"
        The stderr should equal ""
      End

      It "should fail when multiple primaries detected"
        check_redis_role() {
          echo "primary"
        }
        When call check_redis_kernel_status
        The status should be failure
        The stderr should include "Multiple primaries detected"
        The stdout should equal ""
      End

      It "should fail when no primary found"
        check_redis_role() {
          echo "secondary"
        }
        When call check_redis_kernel_status
        The status should be failure
        The stderr should include "No primary found"
        The stdout should equal ""
      End
    End

    Context "execute_sub_command()"
      It "should succeed with OK response"
        redis-cli() {
          echo "OK"
        }
        When call execute_sub_command "localhost" "6379" "password" "PING"
        The status should be success
        The stdout should include "Command executed successfully"
        The stderr should equal ""
      End

      It "should fail with non-OK response"
        redis-cli() {
          echo "ERROR"
        }
        When call execute_sub_command "localhost" "6379" "password" "PING"
        The status should be failure
        The stderr should include "Command failed"
        The stdout should include "ERROR"
      End

      It "should fail when redis-cli fails"
        redis-cli() {
          return 1
        }
        When call execute_sub_command "localhost" "6379" "password" "PING"
        The status should be failure
        The stderr should include "Command failed"
        The stdout should include "execute_sub_command output:"
      End
    End

    Context "execute_sentinel_failover()"
      setup() {
        export SENTINEL_POD_FQDN_LIST="sentinel1,sentinel2"
        export SENTINEL_SERVICE_PORT="26379"
        export SENTINEL_PASSWORD="sentinel_pass"
      }
      Before 'setup'

      cleanup() {
        unset SENTINEL_POD_FQDN_LIST
        unset SENTINEL_SERVICE_PORT
        unset SENTINEL_PASSWORD
      }
      After 'cleanup'

      It "should succeed with first sentinel"
        execute_sub_command() {
          echo "OK"
          return 0
        }
        When call execute_sentinel_failover "redis"
        The status should be success
        The stdout should include "Sentinel failover started with sentinel1"
        The stderr should equal ""
      End

      It "should fail when all sentinels fail"
        execute_sub_command() {
          return 1
        }
        call_func_with_retry() {
          return 1
        }
        When call execute_sentinel_failover "redis"
        The status should be failure
        The stderr should include "All Sentinel failover attempts failed"
      End
    End
  End

  Describe "Switchover Tests"
    setup() {
      export REDIS_DEFAULT_PASSWORD="redis_pass"
      export SENTINEL_POD_FQDN_LIST="sentinel1,sentinel2"
      export REDIS_POD_FQDN_LIST="redis1,redis2,redis3"
      export KB_SWITCHOVER_CANDIDATE_FQDN="redis2"
      export REDIS_COMPONENT_NAME="redis"
      export SERVICE_PORT="6379"
      export KB_SWITCHOVER_ROLE="primary"
      export SENTINEL_SERVICE_PORT="26379"
      export SENTINEL_PASSWORD="sentinel_pass"
      export COMPONENT_REPLICAS="2"
      MOCK_RESPONSES=()
      RESPONSE_INDEX=0
    }
    Before 'setup'

    cleanup() {
      unset REDIS_DEFAULT_PASSWORD
      unset SENTINEL_POD_FQDN_LIST
      unset REDIS_POD_FQDN_LIST
      unset KB_SWITCHOVER_CANDIDATE_FQDN
      unset REDIS_COMPONENT_NAME
      unset SERVICE_PORT
      unset KB_SWITCHOVER_ROLE
      unset SENTINEL_SERVICE_PORT
      unset SENTINEL_PASSWORD
      unset MOCK_RESPONSES
      unset RESPONSE_INDEX
      unset COMPONENT_REPLICAS
    }
    After 'cleanup'

    Context "switchover_with_candidate()"
      It "should execute successful switchover"
        check_redis_role() {
          if [ "$1" = "redis2" ]; then
            echo "secondary"
          else
            echo "primary"
          fi
        }
        check_redis_kernel_status() { return 0; }
        set_redis_priorities() { return 0; }
        wait_sentinel_sees_priority_bias() { return 0; }
        execute_sentinel_failover() { return 0; }
        check_switchover_result() { return 0; }
        recover_redis_priorities() {
          echo "All FalkorDB config set replica-priority recovered."
          return 0
        }

        When call switchover_with_candidate
        The status should be success
        The stdout should include "All FalkorDB config set replica-priority recovered"
        The stderr should equal ""
      End

      It "should restore priorities when Sentinel cache confirmation fails"
        load_common_library() { return 0; }
        check_environment_exist() { return 0; }
        export KB_SWITCHOVER_CANDIDATE_FQDN="redis2"
        check_redis_role() { echo "secondary"; }
        check_redis_kernel_status() { echo "redis1"; }
        set_redis_priorities() {
          priorities_mutated=true
          return 0
        }
        wait_sentinel_sees_priority_bias() { return 1; }
        recover_redis_priorities() {
          echo "RESTORED"
          priorities_mutated=false
          return 0
        }
        When call run_switchover_action
        The status should be failure
        The stdout should include "RESTORED"
      End

      It "should restore priorities when Sentinel failover fails"
        load_common_library() { return 0; }
        check_environment_exist() { return 0; }
        export KB_SWITCHOVER_CANDIDATE_FQDN="redis2"
        check_redis_role() { echo "secondary"; }
        check_redis_kernel_status() { echo "redis1"; }
        set_redis_priorities() {
          priorities_mutated=true
          return 0
        }
        wait_sentinel_sees_priority_bias() { return 0; }
        execute_sentinel_failover() { return 1; }
        recover_redis_priorities() {
          echo "RESTORED"
          priorities_mutated=false
          return 0
        }
        When call run_switchover_action
        The status should be failure
        The stdout should include "RESTORED"
      End

      It "should wait for all Sentinel caches to observe the target bias"
        export SENTINEL_POD_FQDN_LIST="sentinel1,sentinel2"
        export REDIS_POD_FQDN_LIST="redis1,redis2,redis3"
        ORIGINAL_PRIORITIES["redis1"]=100
        ORIGINAL_PRIORITIES["redis2"]=100
        ORIGINAL_PRIORITIES["redis3"]=0
        redis_replica_announce_address() {
          case "$1" in
            redis2) printf '%s\t%s\n' "10.0.0.2" "31002" ;;
            redis3) printf '%s\t%s\n' "10.0.0.3" "31003" ;;
          esac
        }
        sentinel_observed_replica_priority() {
          case "$1:$2:$3" in
            sentinel1:10.0.0.2:31002|sentinel2:10.0.0.2:31002) echo "1" ;;
            sentinel1:10.0.0.3:31003|sentinel2:10.0.0.3:31003) echo "0" ;;
          esac
        }
        When call wait_sentinel_sees_priority_bias "redis2" "redis1"
        The status should be success
        The stdout should include "All Sentinel replica priority caches confirmed"
      End

      It "should parse the target priority by its advertised address"
        export REDIS_CLI_TLS_CMD=""
        export CUSTOM_SENTINEL_MASTER_NAME="redis"
        export SENTINEL_SERVICE_PORT="26379"
        export SENTINEL_PASSWORD=""
        redis-cli() {
          cat <<'EOF'
1) "name"
2) "not-redis2.redis-headless.default.svc.cluster.local:6379"
3) "slave-priority"
4) "100"
5) "name"
6) "10.0.0.2:31002"
7) "ip"
8) "10.0.0.2"
9) "port"
10) "31002"
11) "slave-priority"
12) "1"
EOF
        }
        When call sentinel_observed_replica_priority "sentinel1" "10.0.0.2" "31002"
        The status should be success
        The output should equal "1"
      End

      It "should parse an exact target after an address collision"
        export REDIS_CLI_TLS_CMD=""
        export CUSTOM_SENTINEL_MASTER_NAME="redis"
        export SENTINEL_SERVICE_PORT="26379"
        export SENTINEL_PASSWORD=""
        redis-cli() {
          cat <<'EOF'
1) "name"
2) "10.0.0.2:31001"
3) "ip"
4) "10.0.0.2"
5) "port"
6) "31001"
7) "slave-priority"
8) "100"
9) "name"
10) "10.0.0.2:31002"
11) "ip"
12) "10.0.0.2"
13) "port"
14) "31002"
15) "slave-priority"
16) "1"
EOF
        }
        When call sentinel_observed_replica_priority "sentinel1" "10.0.0.2" "31002"
        The status should be success
        The output should equal "1"
      End

      It "should read and resolve an advertised hostname from Redis"
        getent() {
          printf '%s\n' "10.0.0.2 advertised.example"
        }
        redis_config_get() {
          printf '%s\n' \
            "replica-announce-ip" "advertised.example" \
            "replica-announce-port" "31002"
        }
        When call redis_replica_announce_address "redis2.redis-headless.default.svc.cluster.local"
        The status should be success
        The output should equal "$(printf 'advertised.example,10.0.0.2\t31002')"
      End

      It "should use the service port for a fixed Pod IP with announce-port zero"
        redis_service_port="6379"
        redis_config_get() {
          printf '%s\n' \
            "replica-announce-ip" "10.0.0.22" \
            "replica-announce-port" "0"
        }
        When call redis_replica_announce_address "redis2.redis-headless.default.svc.cluster.local"
        The status should be success
        The output should equal "$(printf '10.0.0.22\t6379')"
      End

      It "should reject an exact announce address collision across replicas"
        register_exact_collision() {
          ANNOUNCE_TUPLE_OWNERS=()
          ANNOUNCE_IDENTITY_ERROR=""
          register_replica_announce_identity "redis2" "10.0.0.2" "31002"
          register_replica_announce_identity "redis3" "10.0.0.2" "31002"
        }
        When call register_exact_collision
        The status should be failure
        The stderr should include "Replica announce identity 10.0.0.2:31002 is shared by redis2 and redis3"
      End

      It "should reject a resolved address collision across advertised hostnames"
        register_alias_collision() {
          ANNOUNCE_TUPLE_OWNERS=()
          ANNOUNCE_IDENTITY_ERROR=""
          register_replica_announce_identity \
            "redis2" "replica-a.example,10.0.0.9" "31002"
          register_replica_announce_identity \
            "redis3" "replica-b.example,10.0.0.9" "31002"
        }
        When call register_alias_collision
        The status should be failure
        The stderr should include "Replica announce identity 10.0.0.9:31002 is shared by redis2 and redis3"
      End

      It "should allow replicas to share an address when their ports differ"
        register_distinct_ports() {
          ANNOUNCE_TUPLE_OWNERS=()
          ANNOUNCE_IDENTITY_ERROR=""
          register_replica_announce_identity "redis2" "10.0.0.2" "31002"
          register_replica_announce_identity "redis3" "10.0.0.2" "31003"
        }
        When call register_distinct_ports
        The status should be success
        The stderr should equal ""
      End

      It "should reject a requested candidate absent from the exact pod list"
        export REDIS_POD_FQDN_LIST="redis1.redis-headless.default.svc.cluster.local,redis2.redis-headless.default.svc.cluster.local"
        export KB_SWITCHOVER_CANDIDATE_FQDN="redis2.other-headless.other.svc.cluster.local"
        check_redis_role() {
          echo "secondary"
        }
        When call switchover_with_candidate
        The status should be failure
        The stderr should include "not an exact member of REDIS_POD_FQDN_LIST"
      End

      It "should fail a successful action when priority cleanup fails"
        load_common_library() { return 0; }
        check_environment_exist() { return 0; }
        export KB_SWITCHOVER_CANDIDATE_FQDN="redis2"
        switchover_with_candidate() {
          priorities_mutated=true
          return 0
        }
        recover_redis_priorities() { return 1; }
        When call run_switchover_action
        The status should be failure
        The stderr should include "Failed to restore"
      End

      It "should keep priority recovery retries within the supervisor grace"
        ORIGINAL_PRIORITIES=()
        ORIGINAL_PRIORITIES["redis1"]=100
        ORIGINAL_PRIORITIES["redis2"]=100
        ORIGINAL_PRIORITIES["redis3"]=0
        call_func_with_retry() {
          echo "RETRY_CONTRACT:$1:$2:$3:$4"
          return 0
        }
        When call recover_redis_priorities
        The status should be success
        The output should include "RETRY_CONTRACT:2:1:execute_sub_command:redis1"
        The output should include "RETRY_CONTRACT:2:1:execute_sub_command:redis2"
        The output should include "RETRY_CONTRACT:2:1:execute_sub_command:redis3"
      End

      It "should complete real parallel timeout retries within the cleanup grace"
        run_real_priority_recovery_budget_case() {
          local stub_dir
          local started
          local elapsed
          stub_dir=$(mktemp -d)
          printf '%s\n' '#!/bin/bash' 'sleep 60' > "$stub_dir/redis-cli"
          chmod +x "$stub_dir/redis-cli"
          PATH="$stub_dir:$PATH"
          ut_mode="false"
          ORIGINAL_PRIORITIES=()
          ORIGINAL_PRIORITIES["redis1"]=100
          ORIGINAL_PRIORITIES["redis2"]=100
          ORIGINAL_PRIORITIES["redis3"]=0
          started=$SECONDS
          recover_redis_priorities
          local status=$?
          elapsed=$((SECONDS - started))
          rm -rf "$stub_dir"
          echo "RECOVERY_ELAPSED:$elapsed"
          [[ $status -ne 0 && $elapsed -ge 10 && $elapsed -lt 20 ]]
        }
        When call run_real_priority_recovery_budget_case
        The status should be success
        The output should include "RECOVERY_ELAPSED:"
        The stderr should include "failed after 2 retries."
      End

      It "should route the production main through the bounded supervisor"
        supervise_switchover_action() {
          echo "PRODUCTION_SUPERVISOR:$*"
          return 23
        }
        When call falkordb_switchover_main payload
        The status should be failure
        The output should include \
          "PRODUCTION_SUPERVISOR:420 60 /bin/bash"
        The output should include \
          "--falkordb-switchover-deadline-child payload"
      End

      It "should run TERM cleanup when a supervised child hangs"
        When run supervise_switchover_action 1 2 /bin/bash -c \
          'trap "echo TERM_CLEANUP; exit 1" TERM; while :; do sleep 1; done'
        The status should be failure
        The output should include "TERM_CLEANUP"
        The stderr should include "Terminated"
      End

      It "should force-kill a supervised child that ignores TERM"
        run_forced_kill_case() {
          (
            supervise_switchover_action 1 1 /bin/bash -c \
              'trap "" TERM; while :; do sleep 1; done'
          ) 2>/dev/null
          local status=$?
          echo "FORCED_KILL_STATUS:$status"
          return "$status"
        }
        When call run_forced_kill_case
        The status should be failure
        The output should include "FORCED_KILL_STATUS:"
        The stderr should include "Killed"
      End

      It "should fail when candidate is primary"
        check_redis_role() {
          echo "primary"
        }
        When call switchover_with_candidate
        The status should be failure
        The stderr should include "not in secondary role"
        The stdout should equal ""
      End
    End

    Context "switchover_without_candidate()"
      It "should execute successful switchover"
        MOCK_RESPONSES=("redis1" "redis2")
        check_redis_kernel_status() {
          local response=${MOCK_RESPONSES[$RESPONSE_INDEX]}
          RESPONSE_INDEX=$((RESPONSE_INDEX + 1))
          echo "$response"
        }
        execute_sentinel_failover() { return 0;}
        check_switchover_result() { return 0; }
        When call switchover_without_candidate
        The status should be success
      End

      It "should fail when initial status check fails"
        check_redis_kernel_status() {
          return 1
        }
        When call switchover_without_candidate
        The status should be failure
        The stdout should equal ""
      End

      It "should fail when sentinel failover fails"
        check_redis_kernel_status() {
          echo "redis1"
        }
        execute_sentinel_failover() {
          return 1
        }
        When call switchover_without_candidate
        The status should be failure
        The stdout should equal ""
      End
    End

    Context "check_switchover_result()"
      It "should succeed when expected master is achieved"
        check_redis_kernel_status() {
          echo "redis2"
        }
        When call check_switchover_result "redis2" ""
        The status should be success
        The stdout should include "Switchover successful: redis2 is now master"
        The stderr should equal ""
      End

      It "should succeed when switched from initial master"
        check_redis_kernel_status() {
          echo "redis2"
        }
        When call check_switchover_result "" "redis1"
        The status should be success
        The stdout should include "Switchover successful: new master is redis2"
        The stderr should equal ""
      End

      It "should fail when neither expected nor initial master specified"
        check_redis_kernel_status() {
          echo "redis2"
        }
        When call check_switchover_result "" ""
        The status should be failure
        The stderr should include "Neither expected_master nor initial_master specified"
        The stdout should equal ""
      End
    End
  End
End
