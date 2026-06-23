# shellcheck shell=bash
# shellcheck disable=SC2034
# shellcheck disable=SC2154

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_reconfigure_config_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

# Helper: extract CONFIG SET/GET key from redis-cli args
_redis_cli_last_key() {
  local n=$#
  local key="${!n}"
  echo "$key"
}

# Helper: extract CONFIG operation (SET or GET) from redis-cli args
_redis_cli_operation() {
  for arg in "$@"; do
    case "$arg" in
      CONFIG) local found=1 ;;
      SET|GET) [ "${found:-}" = "1" ] && echo "$arg" && return ;;
    esac
  done
}

Describe "Redis Reconfigure Config (argv-based)"
  Include ../scripts/redis-reconfigure-config.sh

  Describe "to_bytes()"
    It "passes plain numbers through"
      When call to_bytes "67108864"
      The output should eq "67108864"
    End

    It "converts kb to bytes"
      When call to_bytes "64kb"
      The output should eq "65536"
    End

    It "converts KB to bytes"
      When call to_bytes "64KB"
      The output should eq "65536"
    End

    It "converts mb to bytes"
      When call to_bytes "64mb"
      The output should eq "67108864"
    End

    It "converts gb to bytes"
      When call to_bytes "1gb"
      The output should eq "1073741824"
    End

    It "converts GB to bytes"
      When call to_bytes "2GB"
      The output should eq "2147483648"
    End

    It "passes non-numeric strings through"
      When call to_bytes "yes"
      The output should eq "yes"
    End
  End

  Describe "normalize_tokens()"
    It "passes plain numbers through"
      When call normalize_tokens "replica 268435456 67108864 60"
      The output should eq "replica 268435456 67108864 60"
    End

    It "converts memory units to bytes"
      When call normalize_tokens "replica 256mb 64mb 60"
      The output should eq "replica 268435456 67108864 60"
    End

    It "handles mixed units"
      When call normalize_tokens "pubsub 32mb 8mb 60"
      The output should eq "pubsub 33554432 8388608 60"
    End

    It "passes all-zero tuple through"
      When call normalize_tokens "normal 0 0 0"
      The output should eq "normal 0 0 0"
    End
  End

  Describe "values_match()"
    It "matches identical strings"
      When call values_match "100" "100"
      The status should be success
    End

    It "rejects different strings"
      When call values_match "100" "200"
      The status should be failure
    End

    It "matches memory format 1gb vs bytes"
      When call values_match "1073741824" "1gb"
      The status should be success
    End

    It "matches memory format bytes vs 1GB"
      When call values_match "1073741824" "1GB"
      The status should be success
    End

    It "matches memory format 64mb vs bytes"
      When call values_match "67108864" "64mb"
      The status should be success
    End

    It "rejects mismatched byte values"
      When call values_match "67108864" "1gb"
      The status should be failure
    End

    It "matches identical non-numeric strings"
      When call values_match "yes" "yes"
      The status should be success
    End

    It "rejects different non-numeric strings"
      When call values_match "yes" "no"
      The status should be failure
    End
  End

  Describe "apply_parameter()"
    Context "successful CONFIG SET with matching readback"
      redis-cli() {
        local op
        op=$(_redis_cli_operation "$@")
        case "$op" in
          SET) echo "OK"; return 0 ;;
          GET)
            local key
            key=$(_redis_cli_last_key "$@")
            case "$key" in
              maxclients) printf 'maxclients\n10003\n' ;;
              maxmemory) printf 'maxmemory\n1073741824\n' ;;
              hz) printf 'hz\n25\n' ;;
            esac
            return 0 ;;
        esac
      }

      setup() {
        service_port=6379
        auth_arg=""
      }
      Before "setup"

      It "applies maxclients and verifies readback"
        When call apply_parameter "maxclients" "10003"
        The status should be success
        The stdout should include "OK"
        The stderr should include "applied and verified"
      End

      It "applies hz and verifies readback"
        When call apply_parameter "hz" "25"
        The status should be success
        The stdout should include "OK"
        The stderr should include "applied and verified"
      End
    End

    Context "successful CONFIG SET with memory format readback"
      redis-cli() {
        local op
        op=$(_redis_cli_operation "$@")
        case "$op" in
          SET) echo "OK"; return 0 ;;
          GET)
            printf 'maxmemory\n1073741824\n'
            return 0 ;;
        esac
      }

      setup() {
        service_port=6379
        auth_arg=""
      }
      Before "setup"

      It "matches 1gb value against byte readback"
        When call apply_parameter "maxmemory" "1gb"
        The status should be success
        The stdout should include "OK"
        The stderr should include "applied and verified"
      End
    End

    Context "CONFIG SET fails"
      redis-cli() {
        local op
        op=$(_redis_cli_operation "$@")
        case "$op" in
          SET) echo "ERR unknown command"; return 1 ;;
          GET) printf 'maxclients\n10001\n'; return 0 ;;
        esac
      }

      setup() {
        service_port=6379
        auth_arg=""
      }
      Before "setup"

      It "returns failure when CONFIG SET returns error"
        When call apply_parameter "maxclients" "10003"
        The status should be failure
        The stdout should include "ERR unknown command"
        The stderr should include "CONFIG SET maxclients failed"
      End
    End

    Context "readback mismatch"
      redis-cli() {
        local op
        op=$(_redis_cli_operation "$@")
        case "$op" in
          SET) echo "OK"; return 0 ;;
          GET)
            printf 'maxclients\n10001\n'
            return 0 ;;
        esac
      }

      setup() {
        service_port=6379
        auth_arg=""
      }
      Before "setup"

      It "returns failure when readback does not match"
        When call apply_parameter "maxclients" "10003"
        The status should be failure
        The stdout should include "OK"
        The stderr should include "readback mismatch"
        The stderr should include "engine='10001'"
        The stderr should include "expected='10003'"
      End
    End

    Context "readback returns nothing for non-empty value"
      redis-cli() {
        local op
        op=$(_redis_cli_operation "$@")
        case "$op" in
          SET) echo "OK"; return 0 ;;
          GET) printf 'boguskey\n'; return 0 ;;
        esac
      }

      setup() {
        service_port=6379
        auth_arg=""
      }
      Before "setup"

      It "returns failure when CONFIG GET returns no value"
        When call apply_parameter "maxclients" "10003"
        The status should be failure
        The stdout should include "OK"
        The stderr should include "returned nothing after SET"
      End
    End

    Context "with auth password"
      _captured_auth=""
      redis-cli() {
        local op
        op=$(_redis_cli_operation "$@")
        for i in $(seq 1 $#); do
          if [ "${!i}" = "-a" ]; then
            local next=$((i + 1))
            _captured_auth="${!next}"
            break
          fi
        done
        case "$op" in
          SET) echo "OK"; return 0 ;;
          GET) printf 'maxclients\n10003\n'; return 0 ;;
        esac
      }

      setup() {
        service_port=6379
        export REDIS_DEFAULT_PASSWORD="secret123"
        auth_arg="-a secret123"
        _captured_auth=""
      }
      Before "setup"

      cleanup() {
        unset REDIS_DEFAULT_PASSWORD
      }
      After "cleanup"

      It "passes auth flag to redis-cli"
        When call apply_parameter "maxclients" "10003"
        The status should be success
        The stdout should include "OK"
        The stderr should include "applied and verified"
        The variable _captured_auth should eq "secret123"
      End
    End

    Context "with TLS"
      _captured_tls=""
      redis-cli() {
        _captured_tls=""
        for arg in "$@"; do
          case "$arg" in
            --tls|--cert|--key|--cacert) _captured_tls="yes"; break ;;
          esac
        done
        local op
        op=$(_redis_cli_operation "$@")
        case "$op" in
          SET) echo "OK"; return 0 ;;
          GET) printf 'maxclients\n10003\n'; return 0 ;;
        esac
      }

      setup() {
        service_port=6379
        auth_arg=""
        export REDIS_CLI_TLS_CMD="--tls --cert /certs/tls.crt --key /certs/tls.key --cacert /certs/ca.crt"
        _captured_tls=""
      }
      Before "setup"

      cleanup() {
        unset REDIS_CLI_TLS_CMD
      }
      After "cleanup"

      It "passes TLS flags to redis-cli"
        When call apply_parameter "maxclients" "10003"
        The status should be success
        The stdout should include "OK"
        The stderr should include "applied and verified"
        The variable _captured_tls should eq "yes"
      End
    End

    Context "with custom port"
      _captured_port=""
      redis-cli() {
        for i in $(seq 1 $#); do
          if [ "${!i}" = "-p" ]; then
            local next=$((i + 1))
            _captured_port="${!next}"
            break
          fi
        done
        local op
        op=$(_redis_cli_operation "$@")
        case "$op" in
          SET) echo "OK"; return 0 ;;
          GET) printf 'maxclients\n10003\n'; return 0 ;;
        esac
      }

      setup() {
        service_port=6380
        auth_arg=""
        _captured_port=""
      }
      Before "setup"

      It "uses the configured service port"
        When call apply_parameter "maxclients" "10003"
        The status should be success
        The stdout should include "OK"
        The stderr should include "applied and verified"
        The variable _captured_port should eq "6380"
      End
    End

    Context "subkey parameter (e.g. client-output-buffer-limit normal)"
      _captured_set_args=""
      redis-cli() {
        local op
        op=$(_redis_cli_operation "$@")
        case "$op" in
          SET)
            local n=$#
            local val="${!n}"
            local prev=$((n - 1))
            local key="${!prev}"
            _captured_set_args="$key|$val"
            echo "OK"; return 0
            ;;
          GET)
            printf 'client-output-buffer-limit\nnormal 0 0 0 slave 268435456 67108864 60 pubsub 33554432 8388608 60\n'
            return 0
            ;;
        esac
      }

      setup() {
        service_port=6379
        auth_arg=""
        _captured_set_args=""
      }
      Before "setup"

      It "splits subkey from key and prepends to value in CONFIG SET"
        When call apply_parameter "client-output-buffer-limit normal" "0 0 0"
        The status should be success
        The stdout should include "OK"
        The stderr should include "applied and verified"
        The variable _captured_set_args should eq "client-output-buffer-limit|normal 0 0 0"
      End
    End

    Context "subkey replica with slave alias in readback (Redis returns slave for replica)"
      _captured_set_args=""
      redis-cli() {
        local op
        op=$(_redis_cli_operation "$@")
        case "$op" in
          SET)
            local n=$#
            local val="${!n}"
            local prev=$((n - 1))
            local key="${!prev}"
            _captured_set_args="$key|$val"
            echo "OK"; return 0
            ;;
          GET)
            printf 'client-output-buffer-limit\nnormal 0 0 0 slave 268435456 67108864 60 pubsub 33554432 8388608 60\n'
            return 0
            ;;
        esac
      }

      setup() {
        service_port=6379
        auth_arg=""
        _captured_set_args=""
      }
      Before "setup"

      It "matches replica memory-unit value against slave bytes readback"
        When call apply_parameter "client-output-buffer-limit replica" "256mb 64mb 60"
        The status should be success
        The stdout should include "OK"
        The stderr should include "applied and verified"
        The variable _captured_set_args should eq "client-output-buffer-limit|replica 256mb 64mb 60"
      End
    End

    Context "subkey replica with replica in readback (Redis 7+)"
      redis-cli() {
        local op
        op=$(_redis_cli_operation "$@")
        case "$op" in
          SET) echo "OK"; return 0 ;;
          GET)
            printf 'client-output-buffer-limit\nnormal 0 0 0 replica 268435456 67108864 60 pubsub 33554432 8388608 60\n'
            return 0
            ;;
        esac
      }

      setup() {
        service_port=6379
        auth_arg=""
      }
      Before "setup"

      It "matches replica memory-unit value against replica bytes readback"
        When call apply_parameter "client-output-buffer-limit replica" "256mb 64mb 60"
        The status should be success
        The stdout should include "OK"
        The stderr should include "applied and verified"
      End
    End

    Context "subkey parameter with memory units (pubsub 32mb 8mb 60)"
      redis-cli() {
        local op
        op=$(_redis_cli_operation "$@")
        case "$op" in
          SET) echo "OK"; return 0 ;;
          GET)
            printf 'client-output-buffer-limit\nnormal 0 0 0 slave 268435456 67108864 60 pubsub 33554432 8388608 60\n'
            return 0
            ;;
        esac
      }

      setup() {
        service_port=6379
        auth_arg=""
      }
      Before "setup"

      It "matches pubsub memory-unit value against bytes readback"
        When call apply_parameter "client-output-buffer-limit pubsub" "32mb 8mb 60"
        The status should be success
        The stdout should include "OK"
        The stderr should include "applied and verified"
      End
    End

    Context "subkey parameter readback mismatch"
      redis-cli() {
        local op
        op=$(_redis_cli_operation "$@")
        case "$op" in
          SET) echo "OK"; return 0 ;;
          GET)
            printf 'client-output-buffer-limit\nnormal 0 0 0 slave 268435456 67108864 60 pubsub 33554432 8388608 60\n'
            return 0
            ;;
        esac
      }

      setup() {
        service_port=6379
        auth_arg=""
      }
      Before "setup"

      It "fails when subkey value not found in readback"
        When call apply_parameter "client-output-buffer-limit normal" "999 999 999"
        The status should be failure
        The stdout should include "OK"
        The stderr should include "readback does not contain"
      End
    End

    Context "setting empty value"
      redis-cli() {
        local op
        op=$(_redis_cli_operation "$@")
        case "$op" in
          SET) echo "OK"; return 0 ;;
          GET) printf 'notify-keyspace-events\n\n'; return 0 ;;
        esac
      }

      setup() {
        service_port=6379
        auth_arg=""
      }
      Before "setup"

      It "handles empty value CONFIG SET and readback"
        When call apply_parameter "notify-keyspace-events" ""
        The status should be success
        The stdout should include "OK"
        The stderr should include "applied and verified"
      End

      It "normalizes literal double-quote pair to empty string"
        When call apply_parameter "notify-keyspace-events" '""'
        The status should be success
        The stdout should include "OK"
        The stderr should include "applied and verified"
      End
    End
  End

  Describe "init_reconfigure_env()"
    Context "with defaults"
      setup() {
        unset SERVICE_PORT
        unset REDIS_DEFAULT_PASSWORD
      }
      Before "setup"

      It "sets default port and empty auth"
        When call init_reconfigure_env
        The variable service_port should eq "6379"
        The variable auth_arg should eq ""
      End
    End

    Context "with custom port and password"
      setup() {
        export SERVICE_PORT=6380
        export REDIS_DEFAULT_PASSWORD="mypass"
      }
      Before "setup"

      cleanup() {
        unset SERVICE_PORT
        unset REDIS_DEFAULT_PASSWORD
      }
      After "cleanup"

      It "uses custom port and sets auth"
        When call init_reconfigure_env
        The variable service_port should eq "6380"
        The variable auth_arg should eq "-a mypass"
      End
    End
  End
End
