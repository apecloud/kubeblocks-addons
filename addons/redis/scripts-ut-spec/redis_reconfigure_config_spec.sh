# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_reconfigure_config_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

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

  Describe "to_bytes()"
    It "converts kb"
      When call to_bytes "64kb"
      The output should equal "65536"
    End

    It "converts mb"
      When call to_bytes "64mb"
      The output should equal "67108864"
    End

    It "converts gb"
      When call to_bytes "2gb"
      The output should equal "2147483648"
    End

    It "leaves plain numbers unchanged"
      When call to_bytes "67108864"
      The output should equal "67108864"
    End

    It "leaves non-memory strings unchanged"
      When call to_bytes "notice"
      The output should equal "notice"
    End
  End

  Describe "values_match()"
    It "matches identical values"
      When call values_match "67108864" "67108864"
      The status should be success
    End

    It "matches 64mb against 67108864"
      When call values_match "67108864" "64mb"
      The status should be success
    End

    It "matches 64mb against 67108864 (reverse)"
      When call values_match "64mb" "67108864"
      The status should be success
    End

    It "rejects non-matching values"
      When call values_match "100" "200"
      The status should be failure
    End

    It "matches empty values"
      When call values_match "" ""
      The status should be success
    End
  End

  Describe "reconfigure_parameter()"
    setup_base() {
      service_port=6379
      auth_arg=""
      dynamic_allowlist="maxmemory,hz,loglevel,hash-max-listpack-entries,maxmemory-policy,notify-keyspace-events,save"
    }

    Context "non-dynamic parameter is skipped"
      setup() {
        setup_base
      }
      Before "setup"

      It "returns success with INFO message"
        When call reconfigure_parameter "databases" "32"
        The status should be success
        The stderr should include "INFO: databases not in DYNAMIC_ALLOWLIST"
      End
    End

    Context "CONFIG SET succeeds and readback matches"
      setup() {
        setup_base
      }
      Before "setup"

      redis-cli() {
        case "$*" in
          *"CONFIG SET"*)
            echo "OK"
            ;;
          *"CONFIG GET"*)
            printf '%s\n' "maxmemory" "67108864"
            ;;
        esac
      }

      It "applies and verifies successfully"
        When call reconfigure_parameter "maxmemory" "67108864"
        The status should be success
        The stderr should include "INFO: CONFIG SET maxmemory applied"
        The stderr should not include "ERROR"
      End
    End

    Context "CONFIG SET returns error"
      setup() {
        setup_base
      }
      Before "setup"

      redis-cli() {
        case "$*" in
          *"CONFIG SET"*)
            echo "(error) ERR Unsupported CONFIG parameter: badparam"
            ;;
        esac
      }

      It "returns failure with error message"
        When call reconfigure_parameter "maxmemory" "invalid"
        The status should be failure
        The stderr should include "ERROR: CONFIG SET maxmemory"
      End
    End

    Context "readback mismatch is fail-closed"
      setup() {
        setup_base
      }
      Before "setup"

      redis-cli() {
        case "$*" in
          *"CONFIG SET"*)
            echo "OK"
            ;;
          *"CONFIG GET"*)
            printf '%s\n' "maxmemory-policy" "volatile-lru"
            ;;
        esac
      }

      It "returns failure when readback differs"
        When call reconfigure_parameter "maxmemory-policy" "allkeys-lru"
        The status should be failure
        The stderr should include "readback mismatch"
        The stderr should include "engine='volatile-lru'"
        The stderr should include "expected='allkeys-lru'"
      End
    End

    Context "CONFIG GET returns nothing after SET"
      setup() {
        setup_base
      }
      Before "setup"

      redis-cli() {
        case "$*" in
          *"CONFIG SET"*)
            echo "OK"
            ;;
          *"CONFIG GET"*)
            return 0
            ;;
        esac
      }

      It "returns failure with error"
        When call reconfigure_parameter "maxmemory" "67108864"
        The status should be failure
        The stderr should include "ERROR: CONFIG GET maxmemory returned nothing after SET"
      End
    End

    Context "memory value normalization — 64mb readback as 67108864"
      setup() {
        setup_base
      }
      Before "setup"

      redis-cli() {
        case "$*" in
          *"CONFIG SET"*)
            echo "OK"
            ;;
          *"CONFIG GET"*)
            printf '%s\n' "maxmemory" "67108864"
            ;;
        esac
      }

      It "passes when engine normalizes 64mb to 67108864"
        When call reconfigure_parameter "maxmemory" "64mb"
        The status should be success
        The stderr should include "INFO: CONFIG SET maxmemory applied"
        The stderr should not include "ERROR"
      End
    End

    Context "empty value parameter"
      setup() {
        setup_base
      }
      Before "setup"

      redis-cli() {
        case "$*" in
          *"CONFIG SET"*)
            echo "OK"
            ;;
          *"CONFIG GET"*)
            printf '%s\n' "notify-keyspace-events" ""
            ;;
        esac
      }

      It "handles empty value correctly"
        When call reconfigure_parameter "notify-keyspace-events" ""
        The status should be success
        The stderr should not include "ERROR"
      End
    End

    Context "multi-word value (save parameter)"
      setup() {
        setup_base
      }
      Before "setup"

      redis-cli() {
        case "$*" in
          *"CONFIG SET"*)
            echo "OK"
            ;;
          *"CONFIG GET"*)
            printf '%s\n' "save" "3600 1 300 100"
            ;;
        esac
      }

      It "passes with multi-word value"
        When call reconfigure_parameter "save" "3600 1 300 100"
        The status should be success
        The stderr should include "INFO: CONFIG SET save applied"
      End
    End

    Context "missing parameter name"
      setup() {
        setup_base
      }
      Before "setup"

      It "fails with error"
        When run reconfigure_parameter
        The status should be failure
        The stderr should include "missing parameter name"
      End
    End
  End

End
