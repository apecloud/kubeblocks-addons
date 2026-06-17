# shellcheck shell=bash
# shellcheck disable=SC2034
# shellcheck disable=SC2154

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "sync_acl_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Sync ACL Script Tests"
  Include ../scripts/sync-acl.sh

  init() {
    ut_mode="true"
    service_port=6379
  }
  BeforeAll "init"

  Describe "build_redis_base_cmd()"
    It "builds command with password"
      When call build_redis_base_cmd "mypass" ""
      The output should eq "redis-cli  -p 6379 -a mypass"
    End

    It "builds command without password"
      When call build_redis_base_cmd "" ""
      The output should eq "redis-cli  -p 6379"
    End

    It "builds command with TLS flags"
      When call build_redis_base_cmd "mypass" "--tls --insecure"
      The output should eq "redis-cli --tls --insecure -p 6379 -a mypass"
    End
  End

  Describe "fetch_acl_list_from_peers()"
    Context "when a peer returns ACL LIST successfully"
      redis-cli() {
        if echo "$*" | grep -q "ACL LIST"; then
          printf "user default on ~* +@all\n"
          printf "user appuser on >secret ~app:* +@read\n"
          return 0
        fi
        return 1
      }

      It "returns the ACL list"
        When call fetch_acl_list_from_peers "redis-0.svc,redis-1.svc" "redis-1.svc" "redis-cli -p 6379"
        The status should be success
        The output should include "user default"
        The output should include "user appuser"
      End
    End

    Context "when self is the only pod"
      redis-cli() {
        return 1
      }

      It "fails because no peer is available"
        When call fetch_acl_list_from_peers "redis-0.svc" "redis-0.svc" "redis-cli -p 6379"
        The status should be failure
        The stderr should include "Failed to get ACL LIST from other pods"
      End
    End

    Context "when all peers fail"
      redis-cli() {
        return 1
      }

      It "fails with error message"
        When call fetch_acl_list_from_peers "redis-0.svc,redis-1.svc" "redis-0.svc" "redis-cli -p 6379"
        The status should be failure
        The stderr should include "Failed to get ACL LIST from other pods"
      End
    End

    Context "when peer returns empty ACL list"
      redis-cli() {
        if echo "$*" | grep -q "ACL LIST"; then
          echo ""
          return 0
        fi
        return 1
      }

      It "returns success with skip message"
        When call fetch_acl_list_from_peers "redis-0.svc,redis-1.svc" "redis-0.svc" "redis-cli -p 6379"
        The status should be success
        The output should eq ""
        The stderr should include "No ACL rules found"
      End
    End

    Context "when first peer fails but second succeeds"
      redis-cli() {
        local host_arg=""
        for arg in "$@"; do
          if [ "$prev_was_h" = "true" ]; then
            host_arg="$arg"
            break
          fi
          if [ "$arg" = "-h" ]; then
            prev_was_h="true"
          fi
        done

        if echo "$*" | grep -q "ACL LIST"; then
          if [ "$host_arg" = "redis-1.svc" ]; then
            return 1
          fi
          printf "user admin on >adminpass ~* +@all\n"
          return 0
        fi
        return 1
      }

      It "skips self, retries peers, and returns from successful one"
        When call fetch_acl_list_from_peers "redis-0.svc,redis-1.svc,redis-2.svc" "redis-0.svc" "redis-cli -p 6379"
        The status should be success
        The output should include "user admin"
      End
    End
  End

  Describe "apply_acl_rules()"
    Context "with valid non-default user rules"
      redis-cli() {
        echo "OK"
        return 0
      }

      It "applies ACL SETUSER for non-default users and runs ACL save"
        local acl_list
        acl_list=$(printf "user default on ~* +@all\nuser appuser on >secret ~app:* +@read\nuser admin on >adminpass ~* +@all")
        When call apply_acl_rules "$acl_list" "redis-new.svc" "redis-cli -p 6379"
        The status should be success
        The stderr should include "OK"
      End
    End

    Context "with only default user"
      redis-cli() {
        echo "OK"
        return 0
      }

      It "skips default user and only runs ACL save"
        local acl_list="user default on ~* +@all"
        When call apply_acl_rules "$acl_list" "redis-new.svc" "redis-cli -p 6379"
        The status should be success
      End
    End

    Context "with empty lines and invalid format"
      redis-cli() {
        echo "OK"
        return 0
      }

      It "skips empty lines and invalid entries"
        local acl_list
        acl_list=$(printf "\ninvalid line\nuser testuser on >pass ~* +@all\n")
        When call apply_acl_rules "$acl_list" "redis-new.svc" "redis-cli -p 6379"
        The status should be success
      End
    End

    Context "when ACL SETUSER fails"
      redis-cli() {
        if echo "$*" | grep -q "ACL SETUSER"; then
          echo "ERR unknown user" >&2
          return 1
        fi
        echo "OK"
        return 0
      }

      It "propagates the error"
        local acl_list="user baduser on >pass ~* +@all"
        When call apply_acl_rules "$acl_list" "redis-new.svc" "redis-cli -p 6379"
        The status should be failure
      End
    End

    Context "when ACL save fails"
      redis-cli() {
        if echo "$*" | grep -q "ACL save"; then
          return 1
        fi
        echo "OK"
        return 0
      }

      It "propagates the error"
        local acl_list="user testuser on >pass ~* +@all"
        When call apply_acl_rules "$acl_list" "redis-new.svc" "redis-cli -p 6379"
        The status should be failure
      End
    End
  End
End
