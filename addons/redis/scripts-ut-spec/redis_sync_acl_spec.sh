# shellcheck shell=bash
# shellcheck disable=SC2034
# shellcheck disable=SC2154
# shellcheck disable=SC2168

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_sync_acl_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "sync-acl.sh Tests"
  Include ../scripts/sync-acl.sh

  init() {
    ut_mode="true"
  }
  BeforeAll "init"

  Describe "sync_acl()"
    Context "happy path: single non-default user synced"
      setup() {
        export REDIS_POD_FQDN_LIST="pod1.redis.svc,pod2.redis.svc"
        export KB_JOIN_MEMBER_POD_FQDN="pod1.redis.svc"
        export REDIS_DEFAULT_PASSWORD="secret"
        unset SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      cleanup() {
        unset REDIS_POD_FQDN_LIST KB_JOIN_MEMBER_POD_FQDN REDIS_DEFAULT_PASSWORD
      }
      After 'cleanup'

      It "syncs one user and saves ACL"
        redis-cli() {
          if echo "$*" | grep -q "ACL LIST"; then
            echo "user admin on ~* +@all"
            return 0
          elif echo "$*" | grep -q "ACL SETUSER"; then
            echo "OK" >&2
            return 0
          elif echo "$*" | grep -qi "ACL save"; then
            echo "OK" >&2
            return 0
          fi
        }
        When run sync_acl
        The status should be success
        The stdout should eq ""
        The stderr should include "OK"
      End
    End

    Context "self pod skipped in source loop"
      setup() {
        export REDIS_POD_FQDN_LIST="pod1.redis.svc,pod2.redis.svc"
        export KB_JOIN_MEMBER_POD_FQDN="pod1.redis.svc"
        export REDIS_DEFAULT_PASSWORD="secret"
        unset SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      cleanup() {
        unset REDIS_POD_FQDN_LIST KB_JOIN_MEMBER_POD_FQDN REDIS_DEFAULT_PASSWORD
      }
      After 'cleanup'

      It "skips self and fetches ACL from other pod"
        redis-cli() {
          if echo "$*" | grep -q "ACL LIST"; then
            if echo "$*" | grep -q "pod1.redis.svc"; then
              return 1
            fi
            echo "user myuser on ~keys:* +get +set"
            return 0
          elif echo "$*" | grep -q "ACL SETUSER"; then
            echo "OK" >&2
            return 0
          elif echo "$*" | grep -qi "ACL save"; then
            echo "OK" >&2
            return 0
          fi
        }
        When run sync_acl
        The status should be success
        The stdout should eq ""
        The stderr should include "OK"
      End
    End

    Context "fallback to second peer"
      setup() {
        export REDIS_POD_FQDN_LIST="peer1.redis.svc,peer2.redis.svc,peer3.redis.svc"
        export KB_JOIN_MEMBER_POD_FQDN="peer3.redis.svc"
        export REDIS_DEFAULT_PASSWORD="secret"
        unset SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      cleanup() {
        unset REDIS_POD_FQDN_LIST KB_JOIN_MEMBER_POD_FQDN REDIS_DEFAULT_PASSWORD
      }
      After 'cleanup'

      It "falls back to second peer when first fails"
        redis-cli() {
          if echo "$*" | grep -q "ACL LIST"; then
            if echo "$*" | grep -q "peer1.redis.svc"; then
              return 1
            fi
            echo "user backup on ~* +@all"
            return 0
          elif echo "$*" | grep -q "ACL SETUSER"; then
            echo "OK" >&2
            return 0
          elif echo "$*" | grep -qi "ACL save"; then
            echo "OK" >&2
            return 0
          fi
        }
        When run sync_acl
        The status should be success
        The stdout should eq ""
        The stderr should include "OK"
      End
    End

    Context "all peers fail"
      setup() {
        export REDIS_POD_FQDN_LIST="pod1.redis.svc,pod2.redis.svc"
        export KB_JOIN_MEMBER_POD_FQDN="pod3.redis.svc"
        export REDIS_DEFAULT_PASSWORD="secret"
        unset SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      cleanup() {
        unset REDIS_POD_FQDN_LIST KB_JOIN_MEMBER_POD_FQDN REDIS_DEFAULT_PASSWORD
      }
      After 'cleanup'

      It "exits with failure when all ACL LIST calls fail"
        redis-cli() {
          return 1
        }
        When run sync_acl
        The status should be failure
        The stderr should include "Failed to get ACL LIST from other pods"
      End
    End

    Context "empty ACL list"
      setup() {
        export REDIS_POD_FQDN_LIST="pod1.redis.svc,pod2.redis.svc"
        export KB_JOIN_MEMBER_POD_FQDN="pod1.redis.svc"
        export REDIS_DEFAULT_PASSWORD="secret"
        unset SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      cleanup() {
        unset REDIS_POD_FQDN_LIST KB_JOIN_MEMBER_POD_FQDN REDIS_DEFAULT_PASSWORD
      }
      After 'cleanup'

      It "exits success when ACL list is empty"
        redis-cli() {
          if echo "$*" | grep -q "ACL LIST"; then
            echo ""
            return 0
          fi
        }
        When run sync_acl
        The status should be success
        The stderr should include "No ACL rules found in other pods, skip synchronization"
      End
    End

    Context "default user filtered"
      setup() {
        export REDIS_POD_FQDN_LIST="pod1.redis.svc,pod2.redis.svc"
        export KB_JOIN_MEMBER_POD_FQDN="pod1.redis.svc"
        export REDIS_DEFAULT_PASSWORD="secret"
        unset SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      cleanup() {
        unset REDIS_POD_FQDN_LIST KB_JOIN_MEMBER_POD_FQDN REDIS_DEFAULT_PASSWORD
      }
      After 'cleanup'

      It "skips default user, only calls ACL save"
        redis-cli() {
          if echo "$*" | grep -q "ACL LIST"; then
            echo "user default on ~* +@all"
            return 0
          elif echo "$*" | grep -q "ACL SETUSER"; then
            echo "SETUSER-SHOULD-NOT-BE-CALLED" >&2
            return 0
          elif echo "$*" | grep -qi "ACL save"; then
            echo "OK" >&2
            return 0
          fi
        }
        When run sync_acl
        The status should be success
        The stdout should eq ""
        The stderr should not include "SETUSER-SHOULD-NOT-BE-CALLED"
        The stderr should include "OK"
      End
    End

    Context "multiple non-default users"
      setup() {
        export REDIS_POD_FQDN_LIST="pod1.redis.svc,pod2.redis.svc"
        export KB_JOIN_MEMBER_POD_FQDN="pod1.redis.svc"
        export REDIS_DEFAULT_PASSWORD="secret"
        unset SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      cleanup() {
        unset REDIS_POD_FQDN_LIST KB_JOIN_MEMBER_POD_FQDN REDIS_DEFAULT_PASSWORD
      }
      After 'cleanup'

      It "syncs admin and readonly, skips default"
        redis-cli() {
          if echo "$*" | grep -q "ACL LIST"; then
            printf "user admin on ~* +@all\nuser default on ~* +@all\nuser readonly on ~keys:* +get"
            return 0
          elif echo "$*" | grep -q "ACL SETUSER"; then
            echo "SETUSER:$*" >&2
            return 0
          elif echo "$*" | grep -qi "ACL save"; then
            echo "OK" >&2
            return 0
          fi
        }
        When run sync_acl
        The status should be success
        The stdout should eq ""
        The stderr should include "admin"
        The stderr should include "readonly"
        The stderr should not include "SETUSER default"
      End
    End

    Context "with password"
      setup() {
        export REDIS_POD_FQDN_LIST="pod1.redis.svc,pod2.redis.svc"
        export KB_JOIN_MEMBER_POD_FQDN="pod1.redis.svc"
        export REDIS_DEFAULT_PASSWORD="mypassword"
        unset SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      cleanup() {
        unset REDIS_POD_FQDN_LIST KB_JOIN_MEMBER_POD_FQDN REDIS_DEFAULT_PASSWORD
      }
      After 'cleanup'

      It "includes -a flag when password is set"
        redis-cli() {
          if ! echo "$*" | grep -q "\-a mypassword"; then
            echo "MISSING_PASSWORD_FLAG" >&2
            return 1
          fi
          if echo "$*" | grep -q "ACL LIST"; then
            echo "user testuser on ~* +@all"
            return 0
          elif echo "$*" | grep -q "ACL SETUSER"; then
            echo "OK" >&2
            return 0
          elif echo "$*" | grep -qi "ACL save"; then
            echo "OK" >&2
            return 0
          fi
        }
        When run sync_acl
        The status should be success
        The stdout should eq ""
        The stderr should not include "MISSING_PASSWORD_FLAG"
        The stderr should include "OK"
      End
    End

    Context "without password"
      setup() {
        export REDIS_POD_FQDN_LIST="pod1.redis.svc,pod2.redis.svc"
        export KB_JOIN_MEMBER_POD_FQDN="pod1.redis.svc"
        export REDIS_DEFAULT_PASSWORD=""
        unset SERVICE_PORT
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      cleanup() {
        unset REDIS_POD_FQDN_LIST KB_JOIN_MEMBER_POD_FQDN REDIS_DEFAULT_PASSWORD
      }
      After 'cleanup'

      It "omits -a flag when password is empty"
        redis-cli() {
          if echo "$*" | grep -q " -a "; then
            echo "UNEXPECTED_PASSWORD_FLAG" >&2
            return 1
          fi
          if echo "$*" | grep -q "ACL LIST"; then
            echo "user testuser on ~* +@all"
            return 0
          elif echo "$*" | grep -q "ACL SETUSER"; then
            echo "OK" >&2
            return 0
          elif echo "$*" | grep -qi "ACL save"; then
            echo "OK" >&2
            return 0
          fi
        }
        When run sync_acl
        The status should be success
        The stdout should eq ""
        The stderr should not include "UNEXPECTED_PASSWORD_FLAG"
        The stderr should include "OK"
      End
    End

    Context "TLS flags"
      setup() {
        export REDIS_POD_FQDN_LIST="pod1.redis.svc,pod2.redis.svc"
        export KB_JOIN_MEMBER_POD_FQDN="pod1.redis.svc"
        export REDIS_DEFAULT_PASSWORD="secret"
        export REDIS_CLI_TLS_CMD="--tls --cert /certs/tls.crt --key /certs/tls.key --cacert /certs/ca.crt"
        unset SERVICE_PORT
      }
      Before 'setup'

      cleanup() {
        unset REDIS_POD_FQDN_LIST KB_JOIN_MEMBER_POD_FQDN REDIS_DEFAULT_PASSWORD REDIS_CLI_TLS_CMD
      }
      After 'cleanup'

      It "includes TLS flags in redis-cli command"
        redis-cli() {
          if ! echo "$*" | grep -q "\-\-tls"; then
            echo "MISSING_TLS_FLAG" >&2
            return 1
          fi
          if echo "$*" | grep -q "ACL LIST"; then
            echo "user tlsuser on ~* +@all"
            return 0
          elif echo "$*" | grep -q "ACL SETUSER"; then
            echo "OK" >&2
            return 0
          elif echo "$*" | grep -qi "ACL save"; then
            echo "OK" >&2
            return 0
          fi
        }
        When run sync_acl
        The status should be success
        The stdout should eq ""
        The stderr should not include "MISSING_TLS_FLAG"
        The stderr should include "OK"
      End
    End

    Context "custom port"
      setup() {
        export REDIS_POD_FQDN_LIST="pod1.redis.svc,pod2.redis.svc"
        export KB_JOIN_MEMBER_POD_FQDN="pod1.redis.svc"
        export REDIS_DEFAULT_PASSWORD="secret"
        export SERVICE_PORT="6380"
        unset REDIS_CLI_TLS_CMD
      }
      Before 'setup'

      cleanup() {
        unset REDIS_POD_FQDN_LIST KB_JOIN_MEMBER_POD_FQDN REDIS_DEFAULT_PASSWORD SERVICE_PORT
      }
      After 'cleanup'

      It "uses custom port in redis-cli command"
        redis-cli() {
          if ! echo "$*" | grep -q "\-p 6380"; then
            echo "WRONG_PORT" >&2
            return 1
          fi
          if echo "$*" | grep -q "ACL LIST"; then
            echo "user portuser on ~* +@all"
            return 0
          elif echo "$*" | grep -q "ACL SETUSER"; then
            echo "OK" >&2
            return 0
          elif echo "$*" | grep -qi "ACL save"; then
            echo "OK" >&2
            return 0
          fi
        }
        When run sync_acl
        The status should be success
        The stdout should eq ""
        The stderr should not include "WRONG_PORT"
        The stderr should include "OK"
      End
    End
  End
End
