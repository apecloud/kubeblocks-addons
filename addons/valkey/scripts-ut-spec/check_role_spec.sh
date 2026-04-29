# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "check_role_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "Valkey Check-Role Bash Script Tests"
  Include $common_library_file
  Include ../scripts/check-role.sh

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

  Describe "build_cli_cmd()"
    Context "without password or TLS"
      setup() {
        unset VALKEY_DEFAULT_PASSWORD
        unset VALKEY_CLI_TLS_ARGS
      }
      Before "setup"

      It "builds a basic valkey-cli command"
        When call build_cli_cmd
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
        When call build_cli_cmd
        The status should be success
        The stdout should include "-a secret"
      End
    End

    Context "with custom port"
      setup() {
        port="6380"
        unset VALKEY_DEFAULT_PASSWORD
        unset VALKEY_CLI_TLS_ARGS
      }
      Before "setup"

      teardown() {
        port="${KB_SERVICE_PORT:-${SERVICE_PORT:-6379}}"
      }
      After "teardown"

      It "uses the custom port"
        When call build_cli_cmd
        The status should be success
        The stdout should include "-p 6380"
      End
    End
  End

  Describe "role probe output"
    Context "when server reports master"
      It "outputs 'primary'"
        valkey-cli() {
          printf "# Replication\r\nrole:master\r\nconnected_slaves:2\r\n"
        }
        cli_cmd=$(build_cli_cmd)
        role_line=$(${cli_cmd} info replication 2>/dev/null | grep "^role:" | tr -d '\r\n')
        When call bash -c "
          case \"${role_line}\" in
            \"role:master\") echo \"primary\" ;;
            \"role:slave\")  echo \"secondary\" ;;
            *) echo \"unknown\" >&2; exit 1 ;;
          esac
        "
        The status should be success
        The stdout should eq "primary"
      End
    End

    Context "when server reports slave"
      It "outputs 'secondary'"
        valkey-cli() {
          printf "# Replication\r\nrole:slave\r\nmaster_host:valkey-0\r\n"
        }
        cli_cmd=$(build_cli_cmd)
        role_line=$(${cli_cmd} info replication 2>/dev/null | grep "^role:" | tr -d '\r\n')
        When call bash -c "
          case \"${role_line}\" in
            \"role:master\") echo \"primary\" ;;
            \"role:slave\")  echo \"secondary\" ;;
            *) echo \"unknown\" >&2; exit 1 ;;
          esac
        "
        The status should be success
        The stdout should eq "secondary"
      End
    End
  End

  Describe "is_self_host()"
    Context "loopback aliases"
      setup() {
        export CURRENT_POD_NAME="valkey-0"
        export KB_POD_FQDN="valkey-0.valkey-headless.ns.svc.cluster.local"
      }
      Before "setup"

      teardown() {
        unset CURRENT_POD_NAME
        unset KB_POD_FQDN
      }
      After "teardown"

      It "treats 127.0.0.1 as self"
        When call is_self_host "127.0.0.1"
        The status should be success
      End

      It "treats localhost as self"
        When call is_self_host "localhost"
        The status should be success
      End
    End

    Context "pod identity match"
      setup() {
        export CURRENT_POD_NAME="valkey-0"
        export KB_POD_FQDN="valkey-0.valkey-headless.ns.svc.cluster.local"
      }
      Before "setup"

      teardown() {
        unset CURRENT_POD_NAME
        unset KB_POD_FQDN
      }
      After "teardown"

      It "matches when host equals current pod name"
        When call is_self_host "valkey-0"
        The status should be success
      End

      It "matches when host begins with current pod name and a dot (FQDN form)"
        When call is_self_host "valkey-0.valkey-headless.ns.svc.cluster.local"
        The status should be success
      End

      It "rejects an unrelated peer pod"
        When call is_self_host "valkey-1.valkey-headless.ns.svc.cluster.local"
        The status should be failure
      End
    End
  End

  Describe "check_cascade_topology() guards"
    # Each test uses /tmp/valkey_cli_local_calls.$$ to count local-side calls
    # (host begins with 127.0.0.1). State across $(...) subshells survives via
    # this file. Remote-side calls are dispatched by inspecting the -h arg of
    # the mocked valkey-cli invocation.
    setup() {
      export CURRENT_POD_NAME="valkey-1"
      export KB_POD_FQDN="valkey-1.valkey-headless.ns.svc.cluster.local"
      unset VALKEY_DEFAULT_PASSWORD
      unset VALKEY_CLI_TLS_ARGS
      cli_cmd=$(build_cli_cmd)
      LOCAL_CALL_FILE="/tmp/valkey_cli_local_calls.$$"
      rm -f "${LOCAL_CALL_FILE}"
    }
    Before "setup"

    teardown() {
      unset CURRENT_POD_NAME
      unset KB_POD_FQDN
      rm -f "${LOCAL_CALL_FILE}"
      unset LOCAL_CALL_FILE
    }
    After "teardown"

    Context "when local role flips to master mid-check (stale-role race)"
      It "skips REPLICAOF and emits the skip-stale-role marker"
        # Local call 1 (entry):  role:slave, master_host=valkey-0
        # Remote call (valkey-0): role:slave, master_host=valkey-2  (cascade)
        # Local call 2 (re-read): role:master  (Sentinel promoted us mid-check)
        # Expected: emit skip-stale-role, do NOT issue REPLICAOF.
        valkey-cli() {
          local host="" is_info_replication=0
          while [ $# -gt 0 ]; do
            case "$1" in
              -h) host="$2"; shift 2 ;;
              -p|-a) shift 2 ;;
              --no-auth-warning) shift ;;
              info|INFO)
                if [ "${2:-}" = "replication" ]; then
                  is_info_replication=1
                  shift 2
                else
                  shift
                fi
                ;;
              *) shift ;;
            esac
          done
          if [ "${is_info_replication}" -ne 1 ]; then
            return 0
          fi
          if [ "${host}" = "127.0.0.1" ]; then
            local count=0
            [ -f "${LOCAL_CALL_FILE}" ] && count=$(cat "${LOCAL_CALL_FILE}")
            count=$((count + 1))
            echo "${count}" > "${LOCAL_CALL_FILE}"
            if [ "${count}" -eq 1 ]; then
              printf "# Replication\r\nrole:slave\r\nmaster_host:valkey-0\r\nmaster_link_status:up\r\n"
            else
              printf "# Replication\r\nrole:master\r\n"
            fi
          else
            printf "# Replication\r\nrole:slave\r\nmaster_host:valkey-2\r\nmaster_port:6379\r\n"
          fi
        }
        When call check_cascade_topology
        The status should be success
        The stderr should include "skip-stale-role"
        The stderr should not include "Issuing REPLICAOF"
      End
    End

    Context "when cascade chain folds back to self (self-target)"
      It "skips REPLICAOF and emits the skip-self-target marker"
        # Local call 1 (entry):    role:slave, master_host=valkey-0
        # Remote call (valkey-0):  role:slave, master_host=valkey-1  (== self)
        # Local call 2 (re-read):  role:slave  (stale-role guard passes)
        # is_self_host("valkey-1") matches CURRENT_POD_NAME
        # Expected: emit skip-self-target, do NOT issue REPLICAOF.
        valkey-cli() {
          local host="" is_info_replication=0
          while [ $# -gt 0 ]; do
            case "$1" in
              -h) host="$2"; shift 2 ;;
              -p|-a) shift 2 ;;
              --no-auth-warning) shift ;;
              info|INFO)
                if [ "${2:-}" = "replication" ]; then
                  is_info_replication=1
                  shift 2
                else
                  shift
                fi
                ;;
              *) shift ;;
            esac
          done
          if [ "${is_info_replication}" -ne 1 ]; then
            return 0
          fi
          if [ "${host}" = "127.0.0.1" ]; then
            local count=0
            [ -f "${LOCAL_CALL_FILE}" ] && count=$(cat "${LOCAL_CALL_FILE}")
            count=$((count + 1))
            echo "${count}" > "${LOCAL_CALL_FILE}"
            if [ "${count}" -eq 1 ]; then
              printf "# Replication\r\nrole:slave\r\nmaster_host:valkey-0\r\nmaster_link_status:up\r\n"
            else
              printf "# Replication\r\nrole:slave\r\nmaster_host:valkey-0\r\n"
            fi
          else
            printf "# Replication\r\nrole:slave\r\nmaster_host:valkey-1\r\nmaster_port:6379\r\n"
          fi
        }
        When call check_cascade_topology
        The status should be success
        The stderr should include "skip-self-target"
        The stderr should not include "Issuing REPLICAOF"
      End
    End

    Context "when chain leads to a real non-self master (sanity)"
      It "passes both guards and issues REPLICAOF to the real master"
        # Local call 1 (entry):    role:slave, master_host=valkey-0
        # Remote call (valkey-0):  role:slave, master_host=valkey-2  (!= self)
        # Local call 2 (re-read):  role:slave (stale-role guard passes)
        # is_self_host("valkey-2") returns false (we are valkey-1)
        # Expected: emit "Issuing REPLICAOF" with the real-master line.
        valkey-cli() {
          local host="" is_info_replication=0
          while [ $# -gt 0 ]; do
            case "$1" in
              -h) host="$2"; shift 2 ;;
              -p|-a) shift 2 ;;
              --no-auth-warning) shift ;;
              info|INFO)
                if [ "${2:-}" = "replication" ]; then
                  is_info_replication=1
                  shift 2
                else
                  shift
                fi
                ;;
              *) shift ;;
            esac
          done
          if [ "${is_info_replication}" -ne 1 ]; then
            return 0
          fi
          if [ "${host}" = "127.0.0.1" ]; then
            local count=0
            [ -f "${LOCAL_CALL_FILE}" ] && count=$(cat "${LOCAL_CALL_FILE}")
            count=$((count + 1))
            echo "${count}" > "${LOCAL_CALL_FILE}"
            if [ "${count}" -eq 1 ]; then
              printf "# Replication\r\nrole:slave\r\nmaster_host:valkey-0\r\nmaster_link_status:up\r\n"
            else
              printf "# Replication\r\nrole:slave\r\nmaster_host:valkey-0\r\n"
            fi
          else
            printf "# Replication\r\nrole:slave\r\nmaster_host:valkey-2\r\nmaster_port:6379\r\n"
          fi
        }
        When call check_cascade_topology
        The status should be success
        The stderr should include "Issuing REPLICAOF"
        The stderr should not include "skip-stale-role"
        The stderr should not include "skip-self-target"
      End
    End
  End
End
