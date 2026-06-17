# shellcheck shell=bash
# shellcheck disable=SC2034
# shellcheck disable=SC2154

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_account_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Redis Account Script Tests"
  Include ../scripts/redis-account.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  # BSD paste (macOS) rejects GNU-style combined flags like -sd,
  # Override paste to normalize arguments for cross-platform compatibility
  paste() {
    if [ "$1" = "-sd," ]; then
      shift
      command paste -s -d , "$@" -
    else
      command paste "$@"
    fi
  }

  Describe "env_pre_check()"
    Context "when ACL_COMMAND is empty"
      setup() {
        export ACL_COMMAND=""
        export REDIS_DEFAULT_USER="default"
      }
      Before "setup"

      It "exits with failure"
        When run env_pre_check
        The status should be failure
        The stdout should include "ACL_COMMAND is empty"
      End
    End

    Context "when REDIS_DEFAULT_USER is empty"
      setup() {
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REDIS_DEFAULT_USER=""
      }
      Before "setup"

      It "exits with failure"
        When run env_pre_check
        The status should be failure
        The stdout should include "REDIS_DEFAULT_USER is empty"
      End
    End

    Context "when non-shard mode and REDIS_POD_FQDN_LIST is empty"
      setup() {
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REDIS_DEFAULT_USER="default"
        export SHARD_MODE="FALSE"
        export REDIS_POD_FQDN_LIST=""
      }
      Before "setup"

      It "exits with success (graceful skip)"
        When run env_pre_check
        The status should be success
        The stdout should include "REDIS_POD_FQDN_LIST is empty"
      End
    End

    Context "when shard mode and CURRENT_POD_NAME is empty"
      setup() {
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REDIS_DEFAULT_USER="default"
        export SHARD_MODE="TRUE"
        export CURRENT_POD_NAME=""
      }
      Before "setup"

      It "exits with success (graceful skip)"
        When run env_pre_check
        The status should be success
        The stdout should include "CURRENT_POD_NAME is empty"
      End
    End

    Context "when shard mode and CURRENT_SHARD_COMPONENT_NAME is empty"
      setup() {
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REDIS_DEFAULT_USER="default"
        export SHARD_MODE="TRUE"
        export CURRENT_POD_NAME="redis-shard-0"
        export CURRENT_SHARD_COMPONENT_NAME=""
      }
      Before "setup"

      It "exits with success (graceful skip)"
        When run env_pre_check
        The status should be success
        The stdout should include "CURRENT_SHARD_COMPONENT_NAME is empty"
      End
    End

    Context "when shard mode and CLUSTER_NAMESPACE is empty"
      setup() {
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REDIS_DEFAULT_USER="default"
        export SHARD_MODE="TRUE"
        export CURRENT_POD_NAME="redis-shard-0"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard"
        export CLUSTER_NAMESPACE=""
      }
      Before "setup"

      It "exits with success (graceful skip)"
        When run env_pre_check
        The status should be success
        The stdout should include "CLUSTER_NAMESPACE is empty"
      End
    End

    Context "when shard mode and CLUSTER_DOMAIN is empty"
      setup() {
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REDIS_DEFAULT_USER="default"
        export SHARD_MODE="TRUE"
        export CURRENT_POD_NAME="redis-shard-0"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard"
        export CLUSTER_NAMESPACE="default"
        export CLUSTER_DOMAIN=""
      }
      Before "setup"

      It "exits with success (graceful skip)"
        When run env_pre_check
        The status should be success
        The stdout should include "CLUSTER_DOMAIN is empty"
      End
    End

    Context "when non-shard mode with all required vars set"
      setup() {
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REDIS_DEFAULT_USER="default"
        export SHARD_MODE="FALSE"
        export REDIS_POD_FQDN_LIST="redis-0.redis-headless.ns.svc.cluster.local"
      }
      Before "setup"

      It "passes all checks"
        When call env_pre_check
        The status should be success
        The stdout should equal ""
      End
    End

    Context "when shard mode with all required vars set"
      setup() {
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REDIS_DEFAULT_USER="default"
        export SHARD_MODE="TRUE"
        export CURRENT_POD_NAME="redis-shard-0"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard"
        export CLUSTER_NAMESPACE="default"
        export CLUSTER_DOMAIN="cluster.local"
      }
      Before "setup"

      It "passes all checks"
        When call env_pre_check
        The status should be success
        The stdout should equal ""
      End
    End
  End

  Describe "create_post_check()"
    Context "when success_count equals REPLICAS"
      It "exits with success"
        export REPLICAS=2
        When run create_post_check 2
        The status should be success
        The stdout should include "DO ACL COMMAND FOR ALL HOSTS SUCCESS"
      End
    End

    Context "when success_count is less than REPLICAS"
      It "exits with failure"
        export REPLICAS=3
        When run create_post_check 1
        The status should be failure
        The stdout should include "Need to create 3 hosts account, but only 1 hosts account are created"
      End
    End
  End

  Describe "do_acl_command()"
    Context "with FQDN host and successful ACL operations"
      redis-cli() {
        echo "OK"
        return 0
      }

      It "executes ACL command and save for each host"
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REPLICAS=1
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When run do_acl_command "redis-0.redis-headless.ns.svc.cluster.local" "default" "password123"
        The status should be success
        The stdout should include "DO ACL COMMAND FOR HOST:"
        The stdout should include "DO ACL SAVE FOR HOST:"
        The stdout should include "DO ACL COMMAND FOR ALL HOSTS SUCCESS"
      End
    End

    Context "with multiple FQDN hosts"
      redis-cli() {
        echo "OK"
        return 0
      }

      It "iterates all hosts"
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REPLICAS=2
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When run do_acl_command "redis-0.redis-headless.ns.svc,redis-1.redis-headless.ns.svc" "default" "password123"
        The status should be success
        The stdout should include "DO ACL COMMAND FOR ALL HOSTS SUCCESS"
      End
    End

    Context "with IP:port@slot host format"
      redis-cli() {
        echo "OK"
        return 0
      }

      It "parses port from IP:port@slot format"
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REPLICAS=1
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When run do_acl_command "10.96.180.100:31666@3013" "default" "password123"
        The status should be success
        The stdout should include "DO ACL COMMAND FOR HOST:"
        The stdout should include "DO ACL COMMAND FOR ALL HOSTS SUCCESS"
      End
    End

    Context "when ACL command returns ERR"
      redis-cli() {
        if echo "$*" | grep -q "ACL SAVE"; then
          echo "OK"
          return 0
        fi
        echo "ERR unknown command"
        return 0
      }

      It "exits with failure"
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REPLICAS=1
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When run do_acl_command "redis-0.redis-headless.ns.svc" "default" "password123"
        The status should be failure
        The stdout should include "DO ACL COMMAND FOR HOST: redis-0.redis-headless.ns.svc FAILED"
        The stdout should include "Output: ERR unknown command"
      End
    End

    Context "when redis-cli exits non-zero on ACL command"
      redis-cli() {
        if echo "$*" | grep -q "ACL SAVE"; then
          echo "OK"
          return 0
        fi
        echo "Could not connect" >&2
        return 1
      }

      It "exits with failure"
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REPLICAS=1
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When run do_acl_command "redis-0.redis-headless.ns.svc" "default" "password123"
        The status should be failure
        The stdout should include "FAILED"
      End
    End

    Context "when ACL SAVE fails"
      setup() {
        acl_save_call_count=0
      }
      Before "setup"

      redis-cli() {
        if echo "$*" | grep -q "ACL SAVE"; then
          return 1
        fi
        echo "OK"
        return 0
      }

      It "exits with failure"
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REPLICAS=1
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When run do_acl_command "redis-0.redis-headless.ns.svc" "default" "password123"
        The status should be failure
        The stdout should include "DO ACL SAVE FOR HOST: redis-0.redis-headless.ns.svc FAILED"
      End
    End

    Context "when password is empty"
      redis-cli() {
        echo "OK"
        return 0
      }

      It "builds command without -a flag"
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REPLICAS=1
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When run do_acl_command "redis-0.redis-headless.ns.svc" "default" ""
        The status should be success
        The stdout should include "DO ACL COMMAND FOR ALL HOSTS SUCCESS"
      End
    End

    Context "when ACL_COMMAND is empty"
      redis-cli() {
        echo "OK"
        return 0
      }

      It "skips ACL command but still runs ACL SAVE"
        export ACL_COMMAND=""
        export REPLICAS=1
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When run do_acl_command "redis-0.redis-headless.ns.svc" "default" "password123"
        The status should be success
        The stdout should include "ACL_COMMAND IS EMPTY, SKIP ACL COMMAND"
        The stdout should include "DO ACL SAVE FOR HOST:"
      End
    End
  End

  Describe "get_cluster_host_list()"
    Context "when CLUSTER NODES returns valid output"
      redis-cli() {
        printf "abc123 10.0.0.1:6379@16379,host1.ns.svc master - 0 0 1 connected 0-5460\n"
        printf "def456 10.0.0.2:6379@16379,host2.ns.svc master - 0 0 2 connected 5461-10922\n"
        printf "ghi789 10.0.0.3:6379@16379,host3.ns.svc slave abc123 0 0 3 connected\n"
        return 0
      }

      It "parses host list from second field comma-separated second element"
        export CURRENT_POD_NAME="redis-shard-0"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard"
        export CLUSTER_NAMESPACE="default"
        export CLUSTER_DOMAIN="cluster.local"
        export REDIS_DEFAULT_USER="default"
        export REDIS_DEFAULT_PASSWORD="password123"
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When call get_cluster_host_list
        The status should be success
        The variable host_list should equal "host1.ns.svc,host2.ns.svc,host3.ns.svc"
      End
    End

    Context "when CLUSTER NODES returns empty or only failed nodes"
      redis-cli() {
        printf "abc123 10.0.0.1:6379@16379,host1.ns.svc master,fail - 0 0 1 connected 0-5460\n"
        return 0
      }

      It "exits with failure"
        export CURRENT_POD_NAME="redis-shard-0"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard"
        export CLUSTER_NAMESPACE="default"
        export CLUSTER_DOMAIN="cluster.local"
        export REDIS_DEFAULT_USER="default"
        export REDIS_DEFAULT_PASSWORD="password123"
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When run get_cluster_host_list
        The status should be failure
        The stdout should include "GET CLUSTER HOST LIST FAILED"
      End
    End

    Context "when REDIS_DEFAULT_PASSWORD is empty"
      redis-cli() {
        printf "abc123 10.0.0.1:6379@16379,host1.ns.svc master - 0 0 1 connected 0-5460\n"
        return 0
      }

      It "builds command without -a flag"
        export CURRENT_POD_NAME="redis-shard-0"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard"
        export CLUSTER_NAMESPACE="default"
        export CLUSTER_DOMAIN="cluster.local"
        export REDIS_DEFAULT_USER="default"
        export REDIS_DEFAULT_PASSWORD=""
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When call get_cluster_host_list
        The status should be success
        The variable host_list should equal "host1.ns.svc"
      End
    End

    Context "when CLUSTER NODES includes noaddr entries"
      redis-cli() {
        printf "abc123 10.0.0.1:6379@16379,host1.ns.svc master - 0 0 1 connected 0-5460\n"
        printf "def456 :0@0, master,noaddr - 0 0 2 connected 5461-10922\n"
        return 0
      }

      It "filters out noaddr entries"
        export CURRENT_POD_NAME="redis-shard-0"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard"
        export CLUSTER_NAMESPACE="default"
        export CLUSTER_DOMAIN="cluster.local"
        export REDIS_DEFAULT_USER="default"
        export REDIS_DEFAULT_PASSWORD="password123"
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When call get_cluster_host_list
        The status should be success
        The variable host_list should equal "host1.ns.svc"
      End
    End
  End

  Describe "main()"
    Context "in non-shard mode with all env vars set"
      redis-cli() {
        echo "OK"
        return 0
      }

      It "runs ACL command on REDIS_POD_FQDN_LIST hosts"
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REDIS_DEFAULT_USER="default"
        export REDIS_DEFAULT_PASSWORD="password123"
        export SHARD_MODE="FALSE"
        export REDIS_POD_FQDN_LIST="redis-0.redis-headless.ns.svc"
        export REPLICAS=1
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When run main
        The status should be success
        The stdout should include "DO ACL COMMAND FOR ALL HOSTS SUCCESS"
      End
    End

    Context "in shard mode with all env vars set"
      redis-cli() {
        if echo "$*" | grep -q "CLUSTER NODES"; then
          printf "abc123 10.0.0.1:6379@16379,host1.ns.svc master - 0 0 1 connected 0-5460\n"
          return 0
        fi
        echo "OK"
        return 0
      }

      It "discovers hosts via CLUSTER NODES and runs ACL command"
        export ACL_COMMAND="ACL SETUSER testuser on >pass ~* +@all"
        export REDIS_DEFAULT_USER="default"
        export REDIS_DEFAULT_PASSWORD="password123"
        export SHARD_MODE="TRUE"
        export CURRENT_POD_NAME="redis-shard-0"
        export CURRENT_SHARD_COMPONENT_NAME="redis-shard"
        export CLUSTER_NAMESPACE="default"
        export CLUSTER_DOMAIN="cluster.local"
        export REPLICAS=1
        export REDIS_CLI_TLS_CMD=""
        service_port=6379
        When run main
        The status should be success
        The stdout should include "DO ACL COMMAND FOR ALL HOSTS SUCCESS"
      End
    End
  End
End
