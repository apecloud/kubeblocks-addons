# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "check_role_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

common_library_file="./common.sh"
generate_common_library $common_library_file

# Contract under test (roleProbe stdout, parsed by the controller with
# `strings.Fields`): `<role>` or `<role> <uint64>`, where the version token is
# the Sentinel config-epoch.
#
# Role resolution order:
#   1. Sentinel component present → `SENTINEL master <VALKEY_COMPONENT_NAME>`
#      on the Sentinel headless service (then the individual Sentinel pods),
#      trust its `runid`: local run_id matches → primary, else secondary,
#      version token = config-epoch.
#   2. Anything unusable on the Sentinel side (not configured, unreachable,
#      no record for that name, non-uint64 epoch, non-hex runid, transient
#      master flags) → local INFO replication, single token.
#   3. Unknown local role → exit 1 (KubeBlocks skips the sample).
Describe "Valkey Check-Role Bash Script Tests"
  Include $common_library_file
  Include ../scripts/check-role.sh

  check_role_script="../scripts/check-role.sh"

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
    _cli_cmd_as_string() {
      build_cli_cmd
      printf '%s' "${cli_cmd[*]}"
    }

    Context "without password or TLS"
      setup() {
        unset VALKEY_DEFAULT_PASSWORD VALKEY_CLI_TLS_ARGS
        export SERVICE_PORT="6379"
      }
      Before "setup"

      It "builds a basic valkey-cli command against loopback"
        When call _cli_cmd_as_string
        The status should be success
        The stdout should include "-h 127.0.0.1"
        The stdout should include "-p 6379"
        The stdout should include "--no-auth-warning"
      End
    End

    Context "with password"
      setup() {
        export VALKEY_DEFAULT_PASSWORD="datapass"
        unset VALKEY_CLI_TLS_ARGS
      }
      Before "setup"

      It "includes -a flag"
        When call _cli_cmd_as_string
        The status should be success
        The stdout should include "-a datapass"
      End
    End

    Context "with TLS"
      setup() {
        unset VALKEY_DEFAULT_PASSWORD
        export VALKEY_CLI_TLS_ARGS="--tls --cacert /etc/pki/tls/ca.crt"
      }
      Before "setup"

      It "appends the TLS flags built by the component vars"
        When call _cli_cmd_as_string
        The status should be success
        The stdout should include "--tls"
        The stdout should include "/etc/pki/tls/ca.crt"
      End
    End

    teardown() {
      unset VALKEY_DEFAULT_PASSWORD VALKEY_CLI_TLS_ARGS
    }
    After "teardown"
  End

  Describe "parse_role_line()"
    It "returns role:master when the server reports master"
      When call parse_role_line $'# Replication\r\nrole:master\r\nconnected_slaves:1\r\n'
      The status should be success
      The stdout should eq "role:master"
    End

    It "returns role:slave when the server reports slave"
      When call parse_role_line $'# Replication\r\nrole:slave\r\nmaster_host:10.0.0.1\r\n'
      The status should be success
      The stdout should eq "role:slave"
    End

    It "returns nothing when INFO is empty (pod startup window)"
      When call parse_role_line ""
      The status should be success
      The stdout should eq ""
    End
  End

  Describe "parse_run_id()"
    It "returns the engine run_id"
      When call parse_run_id $'# Server\r\nredis_version:8.1.3\r\nrun_id:abcdef0123456789\r\n'
      The status should be success
      The stdout should eq "abcdef0123456789"
    End

    It "returns nothing when INFO server has no run_id"
      When call parse_run_id $'# Server\r\nredis_version:8.1.3\r\n'
      The status should be success
      The stdout should eq ""
    End
  End

  Describe "collect_sentinel_targets() — headless service first, pods after"
    It "asks the Sentinel headless service before the individual pods"
      export SENTINEL_HEADLESS_SVC_HOST="sentinel-headless.ns.svc"
      export SENTINEL_POD_FQDN_LIST="s-0.h.ns.svc,s-1.h.ns.svc"
      When call collect_sentinel_targets
      The status should be success
      The line 1 of stdout should eq "sentinel-headless.ns.svc"
      The line 2 of stdout should eq "s-0.h.ns.svc"
      The line 3 of stdout should eq "s-1.h.ns.svc"
    End

    It "drops empty entries and duplicates"
      export SENTINEL_HEADLESS_SVC_HOST="sentinel-headless.ns.svc"
      export SENTINEL_POD_FQDN_LIST=",s-0.h.ns.svc,,sentinel-headless.ns.svc"
      When call collect_sentinel_targets
      The status should be success
      The line 1 of stdout should eq "sentinel-headless.ns.svc"
      The line 2 of stdout should eq "s-0.h.ns.svc"
      The lines of stdout should eq 2
    End

    It "uses only the pod list when the headless service is not rendered"
      unset SENTINEL_HEADLESS_SVC_HOST
      export SENTINEL_POD_FQDN_LIST="s-0.h.ns.svc"
      When call collect_sentinel_targets
      The status should be success
      The line 1 of stdout should eq "s-0.h.ns.svc"
    End
  End

  Describe "sentinel_query_master_record() — record validation"
    setup() {
      unset VALKEY_CLI_TLS_ARGS
      export SENTINEL_PASSWORD=""
      sentinel_master_name="mycluster-valkey"
      sentinel_port="26379"
      # `timeout` is exercised as a pass-through, `valkey-cli` is mocked.
      timeout() { shift; "$@"; }
      valkey-cli() {
        case "${FAKE_SENTINEL_MODE}" in
          good)
            printf 'name\nmycluster-valkey\nip\n10.0.0.1\nport\n6379\nrunid\naabbccdd\nflags\nmaster\nconfig-epoch\n7\n'
            ;;
          wrong_name)
            printf 'name\nother-master\nrunid\naabbccdd\nflags\nmaster\nconfig-epoch\n7\n'
            ;;
          epoch_bad)
            printf 'name\nmycluster-valkey\nrunid\naabbccdd\nflags\nmaster\nconfig-epoch\nabc\n'
            ;;
          runid_bad)
            printf 'name\nmycluster-valkey\nrunid\nnot-hex!\nflags\nmaster\nconfig-epoch\n7\n'
            ;;
          flags_bad)
            printf 'name\nmycluster-valkey\nrunid\naabbccdd\nflags\nmaster,s_down\nconfig-epoch\n7\n'
            ;;
          no_answer)
            return 1
            ;;
        esac
      }
    }
    Before "setup"

    teardown() {
      unset FAKE_SENTINEL_MODE SENTINEL_PASSWORD
    }
    After "teardown"

    It "accepts a clean record and exports epoch / runid / flags"
      export FAKE_SENTINEL_MODE="good"
      When call sentinel_query_master_record "sentinel-headless.ns.svc"
      The status should be success
      The variable SENTINEL_RECORD_EPOCH should eq "7"
      The variable SENTINEL_RECORD_RUNID should eq "aabbccdd"
      The variable SENTINEL_RECORD_FLAGS should eq "master"
    End

    It "rejects a record whose name is a different master"
      export FAKE_SENTINEL_MODE="wrong_name"
      When call sentinel_query_master_record "sentinel-headless.ns.svc"
      The status should be failure
      The variable SENTINEL_RECORD_DROP should eq "wrong_master_name"
    End

    It "rejects a non-uint64 config-epoch"
      export FAKE_SENTINEL_MODE="epoch_bad"
      When call sentinel_query_master_record "sentinel-headless.ns.svc"
      The status should be failure
      The variable SENTINEL_RECORD_DROP should eq "epoch_not_uint64"
    End

    It "rejects a malformed runid (non-hex)"
      export FAKE_SENTINEL_MODE="runid_bad"
      When call sentinel_query_master_record "sentinel-headless.ns.svc"
      The status should be failure
      The variable SENTINEL_RECORD_DROP should eq "runid_empty_or_non_hex"
    End

    It "rejects a master flagged s_down / failover_in_progress"
      export FAKE_SENTINEL_MODE="flags_bad"
      When call sentinel_query_master_record "sentinel-headless.ns.svc"
      The status should be failure
      The variable SENTINEL_RECORD_DROP should eq "flags_transient"
    End

    It "rejects an unreachable Sentinel"
      export FAKE_SENTINEL_MODE="no_answer"
      When call sentinel_query_master_record "sentinel-headless.ns.svc"
      The status should be failure
      The variable SENTINEL_RECORD_DROP should eq "no_answer"
    End
  End

  Describe "decide_role() — Sentinel authority vs local fallback"
    It "emits primary <epoch> when run_id matches the Sentinel master runid"
      When call decide_role "role:master" "aaaaaaaa" "aaaaaaaa" "5"
      The status should be success
      The stdout should eq "primary
5"
    End

    It "emits secondary <epoch> when run_id does not match (deposed primary)"
      When call decide_role "role:master" "aaaaaaaa" "bbbbbbbb" "5"
      The status should be success
      The stdout should eq "secondary
5"
    End

    It "emits secondary <epoch> for a local slave while Sentinel is reachable"
      When call decide_role "role:slave" "aaaaaaaa" "bbbbbbbb" "5"
      The status should be success
      The stdout should eq "secondary
5"
    End

    It "falls back to a single token when no Sentinel record was usable"
      When call decide_role "role:master" "aaaaaaaa" "" ""
      The status should be success
      The stdout should eq "primary"
    End

    It "maps local slave to secondary on the fallback path"
      When call decide_role "role:slave" "aaaaaaaa" "" ""
      The status should be success
      The stdout should eq "secondary"
    End

    It "never claims primary with an empty local run_id even if Sentinel answered"
      When call decide_role "role:master" "" "aaaaaaaa" "5"
      The status should be success
      The stdout should eq "secondary
5"
    End

    It "exits non-zero on an unknown local role in the fallback path"
      # `exit 1` must run in a subshell, otherwise it would abort the example.
      decide_role_exit_status() {
        local rc=0
        ( decide_role "$@" ) >/dev/null 2>&1 || rc=$?
        printf '%s' "${rc}"
      }
      When call decide_role_exit_status "role:loading" "" "" ""
      The status should be success
      The stdout should eq "1"
    End

    It "prints the unknown-role diagnostic on stderr"
      decide_role_stderr() {
        # `|| true`: the subshell exits 1 on purpose, the example must not.
        ( decide_role "role:loading" "" "" "" ) 2>&1 >/dev/null || true
      }
      When call decide_role_stderr
      The status should be success
      The stdout should include "unknown role"
    End
  End

  Describe "production script structure (sentinel-first precedence)"
    It "queries Sentinel by the master name this component registered"
      When call grep -F 'sentinel master "${sentinel_master_name}"' "${check_role_script}"
      The status should be success
      The stdout should include "sentinel master"
    End

    It "uses the Sentinel headless service as the first query target"
      When call grep -F 'SENTINEL_HEADLESS_SVC_HOST' "${check_role_script}"
      The status should be success
      The stdout should include "SENTINEL_HEADLESS_SVC_HOST"
    End

    It "caps the number of Sentinel hosts contacted per probe"
      When call grep -F 'sentinel_max_attempts' "${check_role_script}"
      The status should be success
      The stdout should include "sentinel_max_attempts"
    End

    It "wraps each Sentinel attempt in a timeout"
      When call grep -E 'timeout 1 valkey-cli' "${check_role_script}"
      The status should be success
      The stdout should include "timeout 1"
    End

    It "passes the TLS args through to the Sentinel query"
      When call grep -F '${VALKEY_CLI_TLS_ARGS:-}' "${check_role_script}"
      The status should be success
      The stdout should include "VALKEY_CLI_TLS_ARGS"
    End

    It "adds the Sentinel auth flag only when a password is set"
      When call grep -F 'sentinel_auth_args=(-a "${SENTINEL_PASSWORD}")' "${check_role_script}"
      The status should be success
      The stdout should include "SENTINEL_PASSWORD"
    End

    It "keeps no strict-majority quorum logic from the previous design"
      When call grep -E 'min_valid|quorum_keys|split_view' "${check_role_script}"
      The status should be failure
    End

    It "falls back to local INFO when nothing usable came from Sentinel"
      When call grep -F 'local_fallback:' "${check_role_script}"
      The status should be success
      The stdout should include "local_fallback:"
    End

    It "reads INFO replication and INFO server exactly once per probe"
      # Comments mention both commands as well, so only count code lines.
      When call bash -c "grep -vE '^[[:space:]]*#' '${check_role_script}' | grep -cE 'info (replication|server)'"
      The status should be success
      The stdout should eq "2"
    End
  End

  Describe "fork-safety contract — no pipeline parsing"
    # `valkey-cli ... info replication | grep ... | tr ...` spawns one child
    # per stage. When kbagent SIGKILLs this script for exceeding
    # timeoutSeconds, those children are reparented to kbagent's PID 1 (a Go
    # binary that does not reap unrelated children) and pile up as zombies.
    active_pipeline_count() {
      local count
      count=$(grep -vE '^[[:space:]]*(#|$)' "${check_role_script}" \
                | grep -cE '\|[[:space:]]+(grep|tr|awk|sed|cut)[[:space:]]' \
                2>/dev/null || true)
      printf "%s" "${count:-0}"
    }

    It "has no active code line piping INFO output through grep / tr / awk / sed / cut"
      When call active_pipeline_count
      The status should be success
      The stdout should eq "0"
    End

    It "uses the bash builtin while/read/case parse pattern"
      When call grep -E 'while[[:space:]]+IFS=[[:space:]]*read' "${check_role_script}"
      The status should be success
      The stdout should not eq ""
    End

    It "keeps a single-token output path for the local fallback"
      When call decide_role "role:slave" "" "" ""
      The status should be success
      The stdout should eq "secondary"
    End
  End
End
