# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "valkey_self_heal_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Self-Heal Daemon"
  Include $common_library_file
  Include ../scripts/valkey-self-heal.sh

  init() {
    ut_mode="true"
    SELF_HEAL_UT_MODE="true"
    export SERVICE_PORT="6379"
    # Treat any timeout as immediate so info_replication_with_timeout
    # falls through to direct call (deterministic for unit tests).
    export CASCADE_REMOTE_TIMEOUT_SECONDS="0"
  }
  BeforeAll "init"

  cleanup() {
    rm -f "${common_library_file}"
    unset SERVICE_PORT
    unset CASCADE_REMOTE_TIMEOUT_SECONDS
  }
  AfterAll "cleanup"

  Describe "cascade_build_local_cli_cmd()"
    Context "without password or TLS"
      setup() {
        unset VALKEY_DEFAULT_PASSWORD
        unset VALKEY_CLI_TLS_ARGS
      }
      Before "setup"

      It "builds a basic valkey-cli command"
        When call cascade_build_local_cli_cmd
        The status should be success
        The stdout should include "valkey-cli --no-auth-warning"
        The stdout should include "-h 127.0.0.1"
        The stdout should include "-p 6379"
        The stdout should not include " -a "
      End
    End

    Context "with password"
      setup() {
        export VALKEY_DEFAULT_PASSWORD="secret"
      }
      Before "setup"

      teardown() {
        unset VALKEY_DEFAULT_PASSWORD
      }
      After "teardown"

      It "includes -a flag"
        When call cascade_build_local_cli_cmd
        The status should be success
        The stdout should include "-a secret"
      End
    End
  End

  Describe "cascade_extract_replication_field()"
    It "returns the field value"
      When call cascade_extract_replication_field "$(printf 'role:slave\r\nmaster_host:vlk-0\r\n')" "master_host"
      The status should be success
      The stdout should eq "vlk-0"
    End

    It "returns empty when field absent"
      When call cascade_extract_replication_field "$(printf 'role:master\r\n')" "master_host"
      The status should be success
      The stdout should eq ""
    End
  End

  Describe "cascade_is_self_host()"
    setup() {
      export CURRENT_POD_NAME="vlk86-175603-valkey-1"
      export POD_FQDN="vlk86-175603-valkey-1.vlk86-175603-valkey-headless.valkey-86-verify-175603.svc.cluster.local"
    }
    Before "setup"

    teardown() {
      unset CURRENT_POD_NAME
      unset POD_FQDN
    }
    After "teardown"

    It "returns true for 127.0.0.1"
      When call cascade_is_self_host "127.0.0.1"
      The status should be success
    End

    It "returns true for matching pod name"
      When call cascade_is_self_host "vlk86-175603-valkey-1"
      The status should be success
    End

    It "returns true for matching FQDN"
      When call cascade_is_self_host "vlk86-175603-valkey-1.vlk86-175603-valkey-headless.valkey-86-verify-175603.svc.cluster.local"
      The status should be success
    End

    It "returns false for unrelated host"
      When call cascade_is_self_host "vlk86-175603-valkey-0"
      The status should be failure
    End

    It "accepts KB_POD_FQDN as fallback when POD_FQDN unset"
      unset POD_FQDN
      export KB_POD_FQDN="vlk86-175603-valkey-1.vlk86-175603-valkey-headless.valkey-86-verify-175603.svc.cluster.local"
      When call cascade_is_self_host "vlk86-175603-valkey-1.vlk86-175603-valkey-headless.valkey-86-verify-175603.svc.cluster.local"
      The status should be success
      unset KB_POD_FQDN
    End
  End

  Describe "cascade_check_one_round() — repair safeguards"
    setup() {
      export CURRENT_POD_NAME="vlk86-175603-valkey-1"
      export POD_FQDN="vlk86-175603-valkey-1.vlk86-175603-valkey-headless.valkey-86-verify-175603.svc.cluster.local"
      replicaof_calls_file="$(mktemp)"
      info_call_index_file="$(mktemp)"
      printf "0" > "${info_call_index_file}"

      # Stub valkey-cli — emits Replication INFO based on call index + scenario,
      # records REPLICAOF invocations.
      valkey-cli() {
        local cmdline="$*"
        if echo "${cmdline}" | grep -q "REPLICAOF"; then
          local host port
          host=$(echo "${cmdline}" | awk '{ for (i=1; i<=NF; i++) if ($i=="REPLICAOF") { print $(i+1); exit } }')
          port=$(echo "${cmdline}" | awk '{ for (i=1; i<=NF; i++) if ($i=="REPLICAOF") { print $(i+2); exit } }')
          printf "%s %s\n" "${host}" "${port}" >> "${replicaof_calls_file}"
          return 0
        fi
        local call_index
        call_index=$(( $(cat "${info_call_index_file}") + 1 ))
        printf "%s" "${call_index}" > "${info_call_index_file}"
        case "${CASCADE_SCENARIO}:${call_index}" in
          stale:1|self:1|valid:1)
            printf "# Replication\r\nrole:slave\r\nmaster_host:intermediate-master\r\nmaster_link_status:up\r\n"
            ;;
          stale:2)
            printf "# Replication\r\nrole:slave\r\nmaster_host:real-primary\r\nmaster_port:6379\r\n"
            ;;
          stale:3)
            printf "# Replication\r\nrole:master\r\n"
            ;;
          self:2)
            printf "# Replication\r\nrole:slave\r\nmaster_host:vlk86-175603-valkey-1.vlk86-175603-valkey-headless.valkey-86-verify-175603.svc.cluster.local\r\nmaster_port:6379\r\n"
            ;;
          self:3|valid:3)
            printf "# Replication\r\nrole:slave\r\nmaster_host:intermediate-master\r\n"
            ;;
          valid:2)
            printf "# Replication\r\nrole:slave\r\nmaster_host:real-primary\r\nmaster_port:6379\r\n"
            ;;
          notslave:1)
            printf "# Replication\r\nrole:master\r\n"
            ;;
          unreachable:1)
            printf "# Replication\r\nrole:slave\r\nmaster_host:gone-master\r\n"
            ;;
          unreachable:2)
            return 1
            ;;
        esac
      }
    }
    Before "setup"

    teardown() {
      rm -f "${replicaof_calls_file}" "${info_call_index_file}"
      unset CASCADE_SCENARIO
      unset CURRENT_POD_NAME
      unset POD_FQDN
    }
    After "teardown"

    It "early-exits when this pod is not slave"
      export CASCADE_SCENARIO="notslave"
      When call cascade_check_one_round
      The status should be success
      The contents of file "${replicaof_calls_file}" should eq ""
    End

    It "skips repair when remote master unreachable"
      export CASCADE_SCENARIO="unreachable"
      When call cascade_check_one_round
      The status should be success
      The stderr should include "remote-master-unreachable"
      The contents of file "${replicaof_calls_file}" should eq ""
    End

    It "skips repair when local role flips to master between INFO calls (stale-role guard)"
      export CASCADE_SCENARIO="stale"
      When call cascade_check_one_round
      The status should be success
      The stderr should include "skip-stale-role"
      The contents of file "${replicaof_calls_file}" should eq ""
    End

    It "skips repair when computed real-master resolves to self (self-target guard)"
      export CASCADE_SCENARIO="self"
      When call cascade_check_one_round
      The status should be success
      The stderr should include "skip-self-target"
      The contents of file "${replicaof_calls_file}" should eq ""
    End

    It "issues REPLICAOF when cascade detected and no guards trigger"
      export CASCADE_SCENARIO="valid"
      When call cascade_check_one_round
      The status should be success
      The stderr should include "cascading topology"
      The contents of file "${replicaof_calls_file}" should include "real-primary 6379"
    End
  End

  Describe "stall_check_one_round() — full-sync stall detector"
    setup() {
      stall_marker_dir="$(mktemp -d)"
      export STALL_MARKER_FILE="${stall_marker_dir}/sync_stall_since"
      export STALL_THRESHOLD_SECONDS="60"
      restart_calls_file="$(mktemp)"

      # Stub valkey-cli to return INFO output controlled by STALL_SCENARIO.
      valkey-cli() {
        case "${STALL_SCENARIO}" in
          not_slave)
            printf "# Replication\r\nrole:master\r\n"
            ;;
          stalled)
            printf "# Replication\r\nrole:slave\r\nmaster_sync_in_progress:1\r\nmaster_sync_read_bytes:0\r\n"
            ;;
          progressing)
            printf "# Replication\r\nrole:slave\r\nmaster_sync_in_progress:1\r\nmaster_sync_read_bytes:1048576\r\n"
            ;;
          recovered)
            printf "# Replication\r\nrole:slave\r\nmaster_sync_in_progress:0\r\nmaster_sync_read_bytes:0\r\n"
            ;;
          *)
            return 1
            ;;
        esac
      }

      # Stub the restart action to record invocation rather than actually
      # SIGTERMing PID 1 (which would kill shellspec).
      stall_restart_server_for_recovery() {
        printf "called\n" >> "${restart_calls_file}"
      }
    }
    Before "setup"

    teardown() {
      rm -rf "${stall_marker_dir}"
      rm -f "${restart_calls_file}"
      unset STALL_MARKER_FILE
      unset STALL_THRESHOLD_SECONDS
      unset STALL_SCENARIO
    }
    After "teardown"

    It "early-exits when this pod is not slave"
      export STALL_SCENARIO="not_slave"
      When call stall_check_one_round
      The status should be success
      The path "${STALL_MARKER_FILE}" should not be exist
      The contents of file "${restart_calls_file}" should eq ""
    End

    It "creates a marker on first stalled observation"
      export STALL_SCENARIO="stalled"
      When call stall_check_one_round
      The status should be success
      The stderr should include "full-sync stall detected"
      The path "${STALL_MARKER_FILE}" should be exist
      The contents of file "${restart_calls_file}" should eq ""
    End

    It "does not restart while elapsed < threshold"
      export STALL_SCENARIO="stalled"
      # Marker was set just now (current time → elapsed=0).
      date +%s > "${STALL_MARKER_FILE}"
      When call stall_check_one_round
      The status should be success
      The stderr should include "stall ongoing"
      The contents of file "${restart_calls_file}" should eq ""
    End

    It "triggers restart once elapsed >= threshold"
      export STALL_SCENARIO="stalled"
      # Marker timestamp 120s in the past (> 60s threshold).
      echo "$(( $(date +%s) - 120 ))" > "${STALL_MARKER_FILE}"
      When call stall_check_one_round
      The status should be success
      The stderr should include "restarting server"
      The contents of file "${restart_calls_file}" should include "called"
      The path "${STALL_MARKER_FILE}" should not be exist
    End

    It "removes marker when sync resumes (read_bytes > 0)"
      export STALL_SCENARIO="progressing"
      date +%s > "${STALL_MARKER_FILE}"
      When call stall_check_one_round
      The status should be success
      The stderr should include "stall resolved"
      The path "${STALL_MARKER_FILE}" should not be exist
      The contents of file "${restart_calls_file}" should eq ""
    End

    It "removes marker when full-sync completes (sync_in_progress=0)"
      export STALL_SCENARIO="recovered"
      date +%s > "${STALL_MARKER_FILE}"
      When call stall_check_one_round
      The status should be success
      The stderr should include "stall resolved"
      The path "${STALL_MARKER_FILE}" should not be exist
      The contents of file "${restart_calls_file}" should eq ""
    End
  End

  Describe "stall_restart_server_for_recovery() — ut-mode safety"
    It "is a no-op when SELF_HEAL_UT_MODE=true"
      SELF_HEAL_UT_MODE="true"
      When call stall_restart_server_for_recovery
      The status should be success
      The stderr should include "ut_mode"
    End
  End
End
