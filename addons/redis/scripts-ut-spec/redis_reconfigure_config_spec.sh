# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_reconfigure_config_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

# Helper to extract the CONFIG GET key from redis-cli args.
# redis-cli [-tls] -p PORT [-a PASS] CONFIG GET <key>
# The last 3 args are always: CONFIG GET <key>
_redis_cli_get_key() {
  local n=$#
  local key="${!n}"
  local prev=$((n - 1))
  local get="${!prev}"
  local prev2=$((n - 2))
  local config="${!prev2}"
  if [ "$config" = "CONFIG" ] && [ "$get" = "GET" ]; then
    echo "$key"
  fi
}

Describe "Redis Reconfigure Config Script Tests"
  Include ../scripts/redis-reconfigure-config.sh

  Describe "is_dynamic()"
    Context "with a typical allowlist"
      setup() {
        dynamic_allowlist="maxmemory,hz,loglevel,hash-max-listpack-entries"
      }
      Before "setup"

      It "returns success for a listed key"
        When call is_dynamic "maxmemory"
        The status should be success
      End

      It "returns failure for an unlisted key"
        When call is_dynamic "databases"
        The status should be failure
      End

      It "handles hyphenated keys correctly"
        When call is_dynamic "hash-max-listpack-entries"
        The status should be success
      End

      It "does not partial-match substrings"
        When call is_dynamic "max"
        The status should be failure
      End

      It "does not match a superset key"
        When call is_dynamic "maxmemory-policy"
        The status should be failure
      End
    End

    Context "with an empty allowlist"
      setup() {
        dynamic_allowlist=""
      }
      Before "setup"

      It "returns failure for any key"
        When call is_dynamic "maxmemory"
        The status should be failure
      End
    End
  End

  Describe "engine_has_key()"
    setup() {
      engine_dump=$(printf '%s\n' "maxmemory" "67108864" "hz" "10" "loglevel" "notice" "hash-max-listpack-entries" "512")
    }
    Before "setup"

    It "returns success for existing key"
      When call engine_has_key "maxmemory"
      The status should be success
    End

    It "returns failure for missing key"
      When call engine_has_key "databases"
      The status should be failure
    End

    It "handles hyphenated keys"
      When call engine_has_key "hash-max-listpack-entries"
      The status should be success
    End
  End

  Describe "engine_value()"
    setup() {
      engine_dump=$(printf '%s\n' "maxmemory" "67108864" "hz" "10" "loglevel" "notice" "notify-keyspace-events" "")
    }
    Before "setup"

    It "returns the value for a known key"
      When call engine_value "maxmemory"
      The output should equal "67108864"
    End

    It "returns the value for another key"
      When call engine_value "hz"
      The output should equal "10"
    End

    It "returns empty string for a key with empty value"
      When call engine_value "notify-keyspace-events"
      The output should equal ""
    End
  End

  Describe "normalize_value()"
    It "strips surrounding double quotes"
      When call normalize_value '"appendonly.aof"'
      The output should equal "appendonly.aof"
    End

    It "converts quoted empty string to empty"
      When call normalize_value '""'
      The output should equal ""
    End

    It "leaves unquoted values unchanged"
      When call normalize_value "notice"
      The output should equal "notice"
    End

    It "leaves numeric values unchanged"
      When call normalize_value "67108864"
      The output should equal "67108864"
    End

    It "leaves multi-token values unchanged"
      When call normalize_value "0 200 800"
      The output should equal "0 200 800"
    End
  End

  Describe "verify_engine_state()"
    setup() {
      service_port=6379
      auth_arg=""
    }
    Before "setup"

    Context "when CONFIG GET returns the expected value"
      redis-cli() {
        printf '%s\n' "maxmemory" "67108864"
      }

      It "returns success with no INFO output"
        When call verify_engine_state "maxmemory" "67108864"
        The status should be success
        The stderr should equal ""
      End
    End

    Context "when CONFIG GET returns a normalized value"
      redis-cli() {
        printf '%s\n' "auto-aof-rewrite-min-size" "67108864"
      }

      It "returns success with INFO about normalization"
        When call verify_engine_state "auto-aof-rewrite-min-size" "64mb"
        The status should be success
        The stderr should include "INFO: CONFIG SET auto-aof-rewrite-min-size applied"
        The stderr should include "engine reports '67108864'"
        The stderr should include "rendered '64mb'"
      End
    End

    Context "when CONFIG GET returns empty value"
      redis-cli() {
        printf '%s\n' "notify-keyspace-events" ""
      }

      It "returns success when expected value is also empty"
        When call verify_engine_state "notify-keyspace-events" ""
        The status should be success
        The stderr should equal ""
      End
    End

    Context "when CONFIG GET returns nothing"
      redis-cli() {
        return 0
      }

      It "returns failure with ERROR"
        When call verify_engine_state "nonexistent" "value"
        The status should be failure
        The stderr should include "ERROR: CONFIG GET nonexistent returned nothing after SET"
      End
    End
  End

  Describe "reconfigure_from_config_file()"
    tmp_config=""

    setup_base() {
      service_port=6379
      auth_arg=""
      dynamic_allowlist="maxmemory,hz,loglevel,hash-max-listpack-entries"
      wait_interval=0
      wait_max=0
      tmp_config=$(mktemp)
      config_file="$tmp_config"
    }

    cleanup_base() {
      [ -z "$tmp_config" ] || rm -f "$tmp_config"
    }

    Context "config file missing"
      setup() {
        setup_base
        config_file="/nonexistent/redis.conf"

      }
      Before "setup"

      After "cleanup_base"

      It "returns failure with error message"
        When call reconfigure_from_config_file
        The status should be failure
        The stderr should include "ERROR: rendered config not found"
      End
    End

    Context "dynamic intersection — only dynamic keys processed"
      set_called_with=""

      setup() {
        setup_base

        set_called_with=""
        cat > "$tmp_config" <<'CONF'
maxmemory 100000
databases 16
hz 20
cluster-enabled yes
CONF
      }
      Before "setup"

      After "cleanup_base"

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "maxmemory" "67108864" "databases" "16" "hz" "10" "cluster-enabled" "yes"
            ;;
          maxmemory) printf '%s\n' "maxmemory" "100000" ;;
          hz) printf '%s\n' "hz" "20" ;;
        esac
      }

      reload_parameter() {
        set_called_with="${set_called_with}${1}=${2};"
        return 0
      }

      It "only CONFIG SETs dynamic keys that differ from engine"
        When call reconfigure_from_config_file
        The status should be success
        The variable set_called_with should equal "maxmemory=100000;hz=20;"
      End
    End

    Context "static keys are skipped"
      set_called_with=""

      setup() {
        setup_base

        set_called_with=""
        cat > "$tmp_config" <<'CONF'
databases 32
cluster-enabled yes
io-threads 8
CONF
      }
      Before "setup"

      After "cleanup_base"

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "databases" "16" "cluster-enabled" "yes" "io-threads" "4"
            ;;
        esac
      }

      reload_parameter() {
        set_called_with="${set_called_with}${1}=${2};"
        return 0
      }

      It "does not CONFIG SET any static-only keys"
        When call reconfigure_from_config_file
        The status should be success
        The variable set_called_with should equal ""
      End
    End

    Context "unchanged values are skipped"
      set_called_with=""

      setup() {
        setup_base

        set_called_with=""
        cat > "$tmp_config" <<'CONF'
maxmemory 67108864
hz 10
loglevel notice
CONF
      }
      Before "setup"

      After "cleanup_base"

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "maxmemory" "67108864" "hz" "10" "loglevel" "notice"
            ;;
        esac
      }

      reload_parameter() {
        set_called_with="${set_called_with}${1}=${2};"
        return 0
      }

      It "does not CONFIG SET values that already match engine"
        When call reconfigure_from_config_file
        The status should be success
        The variable set_called_with should equal ""
      End
    End

    Context "CONFIG SET failure propagates rc"
      setup() {
        setup_base

        printf '%s\n' "maxmemory 100000" > "$tmp_config"
      }
      Before "setup"

      After "cleanup_base"

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "maxmemory" "67108864"
            ;;
        esac
      }

      reload_parameter() {
        return 1
      }

      It "returns non-zero when reload_parameter fails"
        When call reconfigure_from_config_file
        The status should be failure
        The stderr should include "ERROR: CONFIG SET maxmemory failed"
      End
    End

    Context "post-set verification failure propagates rc"
      setup() {
        setup_base

        printf '%s\n' "maxmemory 100000" > "$tmp_config"
      }
      Before "setup"

      After "cleanup_base"

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "maxmemory" "67108864"
            ;;
          maxmemory)
            # Return nothing to simulate verification failure
            return 0
            ;;
        esac
      }

      reload_parameter() {
        return 0
      }

      It "returns non-zero when post-set verification fails"
        When call reconfigure_from_config_file
        The status should be failure
        The stderr should include "ERROR: CONFIG GET maxmemory returned nothing after SET"
        The stderr should include "ERROR: post-set verification for maxmemory failed"
      End
    End

    Context "comments and blank lines are skipped"
      set_called_with=""

      setup() {
        setup_base

        set_called_with=""
        cat > "$tmp_config" <<'CONF'
# this is a comment
maxmemory 100000

include /etc/redis/extra.conf
loadmodule /opt/redis/modules/bf.so
hz 20
CONF
      }
      Before "setup"

      After "cleanup_base"

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "maxmemory" "67108864" "hz" "10"
            ;;
          maxmemory) printf '%s\n' "maxmemory" "100000" ;;
          hz) printf '%s\n' "hz" "20" ;;
        esac
      }

      reload_parameter() {
        set_called_with="${set_called_with}${1}=${2};"
        return 0
      }

      It "processes only uncommented config lines"
        When call reconfigure_from_config_file
        The status should be success
        The variable set_called_with should equal "maxmemory=100000;hz=20;"
      End
    End

    Context "key-only lines (no value) are skipped"
      set_called_with=""

      setup() {
        setup_base

        set_called_with=""
        printf '%s\n' "maxmemory" > "$tmp_config"
      }
      Before "setup"

      After "cleanup_base"

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "maxmemory" "67108864"
            ;;
        esac
      }

      reload_parameter() {
        set_called_with="${set_called_with}${1}=${2};"
        return 0
      }

      It "skips lines where key equals the full line"
        When call reconfigure_from_config_file
        The status should be success
        The variable set_called_with should equal ""
      End
    End

    Context "hyphenated keys work through full flow"
      set_called_with=""

      setup() {
        setup_base

        set_called_with=""
        printf '%s\n' "hash-max-listpack-entries 256" > "$tmp_config"
      }
      Before "setup"

      After "cleanup_base"

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "hash-max-listpack-entries" "512"
            ;;
          hash-max-listpack-entries)
            printf '%s\n' "hash-max-listpack-entries" "256"
            ;;
        esac
      }

      reload_parameter() {
        set_called_with="${set_called_with}${1}=${2};"
        return 0
      }

      It "correctly processes hyphenated parameter names"
        When call reconfigure_from_config_file
        The status should be success
        The variable set_called_with should equal "hash-max-listpack-entries=256;"
      End
    End

    Context "quoted empty value is idempotent when engine already empty"
      set_called_with=""

      setup() {
        setup_base
        dynamic_allowlist="notify-keyspace-events,maxmemory,hz"

        set_called_with=""
        cat > "$tmp_config" <<'CONF'
notify-keyspace-events ""
maxmemory 67108864
CONF
      }
      Before "setup"

      After "cleanup_base"

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "notify-keyspace-events" "" "maxmemory" "67108864"
            ;;
        esac
      }

      reload_parameter() {
        set_called_with="${set_called_with}${1}=${2};"
        return 0
      }

      It "does not reload when quoted empty matches engine empty"
        When call reconfigure_from_config_file
        The status should be success
        The variable set_called_with should equal ""
      End
    End

    Context "quoted empty to non-empty triggers reload"
      set_called_with=""

      setup() {
        setup_base
        dynamic_allowlist="notify-keyspace-events,maxmemory,hz"

        set_called_with=""
        printf '%s\n' 'notify-keyspace-events "Kx"' > "$tmp_config"
      }
      Before "setup"

      After "cleanup_base"

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "notify-keyspace-events" ""
            ;;
          notify-keyspace-events)
            printf '%s\n' "notify-keyspace-events" "Kx"
            ;;
        esac
      }

      reload_parameter() {
        set_called_with="${set_called_with}${1}=${2};"
        return 0
      }

      It "reloads when rendered quoted value differs from engine empty"
        When call reconfigure_from_config_file
        The status should be success
        The variable set_called_with should equal "notify-keyspace-events=Kx;"
      End
    End

    Context "bounded wait retries until config file changes"
      set_called_with=""
      _retry_count=0

      setup() {
        setup_base
        wait_interval=1
        wait_max=10

        set_called_with=""
        _retry_count=0
        cat > "$tmp_config" <<'CONF'
maxmemory 67108864
hz 10
CONF
      }
      Before "setup"

      After "cleanup_base"

      sleep() { :; }

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "maxmemory" "67108864" "hz" "10"
            ;;
          maxmemory) printf '%s\n' "maxmemory" "200000" ;;
        esac
      }

      sha256sum() {
        _retry_count=$(( _retry_count + 1 ))
        if [ "$_retry_count" -ge 3 ]; then
          printf '%s\n' "maxmemory 200000" > "$tmp_config"
          echo "newhash  $1"
        else
          echo "oldhash  $1"
        fi
      }

      reload_parameter() {
        set_called_with="${set_called_with}${1}=${2};"
        return 0
      }

      It "retries and applies changes when config file updates"
        When call reconfigure_from_config_file
        The status should be success
        The variable set_called_with should equal "maxmemory=200000;"
        The stderr should include "INFO: config file changed after"
        The stderr should include "INFO: applied 1 parameter(s)"
      End
    End

    Context "bounded wait times out gracefully"
      setup() {
        setup_base
        wait_interval=1
        wait_max=4

        cat > "$tmp_config" <<'CONF'
maxmemory 67108864
hz 10
CONF
      }
      Before "setup"

      After "cleanup_base"

      sleep() { :; }

      sha256sum() {
        echo "samehash  $1"
      }

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "maxmemory" "67108864" "hz" "10"
            ;;
        esac
      }

      reload_parameter() {
        return 0
      }

      It "exits 0 with INFO when no diff after timeout"
        When call reconfigure_from_config_file
        The status should be success
        The stderr should include "INFO: no dynamic parameter diff after"
        The stderr should include "config may already be in sync"
      End
    End

    Context "immediate diff skips wait loop"
      set_called_with=""

      setup() {
        setup_base
        wait_interval=1
        wait_max=60

        set_called_with=""
        printf '%s\n' "maxmemory 100000" > "$tmp_config"
      }
      Before "setup"

      After "cleanup_base"

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "maxmemory" "67108864"
            ;;
          maxmemory) printf '%s\n' "maxmemory" "100000" ;;
        esac
      }

      reload_parameter() {
        set_called_with="${set_called_with}${1}=${2};"
        return 0
      }

      It "applies immediately with 0s wait"
        When call reconfigure_from_config_file
        The status should be success
        The variable set_called_with should equal "maxmemory=100000;"
        The stderr should include "INFO: applied 1 parameter(s) after 0s wait"
      End
    End

    Context "post-set verification handles empty value correctly"
      setup() {
        setup_base
        dynamic_allowlist="notify-keyspace-events,maxmemory"

        printf '%s\n' 'notify-keyspace-events ""' > "$tmp_config"
      }
      Before "setup"

      After "cleanup_base"

      redis-cli() {
        local key
        key=$(_redis_cli_get_key "$@")
        case "$key" in
          "'*'"|"*")
            printf '%s\n' "notify-keyspace-events" "Kx"
            ;;
          notify-keyspace-events)
            printf '%s\n' "notify-keyspace-events" ""
            ;;
        esac
      }

      reload_parameter() {
        return 0
      }

      It "verifies empty value post-set without false mismatch"
        When call reconfigure_from_config_file
        The status should be success
        The stderr should not include "ERROR"
        The stderr should include "INFO: applied 1 parameter(s)"
      End
    End
  End
End
