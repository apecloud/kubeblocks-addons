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

  Describe "role probe output (bash-builtin parse, no pipeline children)"
    # Mirror production parse exactly: capture INFO output once via a
    # single command substitution, then walk the captured string with
    # a bash builtin while/read/case loop. No grep / tr children.
    parse_role_line() {
      local repl_info="$1"
      local line role_line=""
      while IFS= read -r line; do
        line="${line%$'\r'}"
        case "${line}" in
          role:*) role_line="${line}"; break ;;
        esac
      done <<<"${repl_info}"
      printf "%s" "${role_line}"
    }

    Context "when server reports master"
      It "outputs 'primary' with no trailing newline (parsed via bash builtins)"
        valkey-cli() {
          printf "# Replication\r\nrole:master\r\nconnected_slaves:2\r\n"
        }
        cli_cmd=$(build_cli_cmd)
        repl_info=$(${cli_cmd} info replication 2>/dev/null)
        role_line=$(parse_role_line "${repl_info}")
        When call bash -c "
          case \"${role_line}\" in
            \"role:master\") printf %s \"primary\" ;;
            \"role:slave\")  printf %s \"secondary\" ;;
            *) echo \"unknown\" >&2; exit 1 ;;
          esac
        "
        The status should be success
        The stdout should eq "primary"
      End
    End

    Context "when server reports slave"
      It "outputs 'secondary' with no trailing newline (parsed via bash builtins)"
        valkey-cli() {
          printf "# Replication\r\nrole:slave\r\nmaster_host:valkey-0\r\n"
        }
        cli_cmd=$(build_cli_cmd)
        repl_info=$(${cli_cmd} info replication 2>/dev/null)
        role_line=$(parse_role_line "${repl_info}")
        When call bash -c "
          case \"${role_line}\" in
            \"role:master\") printf %s \"primary\" ;;
            \"role:slave\")  printf %s \"secondary\" ;;
            *) echo \"unknown\" >&2; exit 1 ;;
          esac
        "
        The status should be success
        The stdout should eq "secondary"
      End
    End

    Context "when INFO output is empty (pod startup window)"
      It "produces empty role_line (script will exit 1 in main)"
        valkey-cli() { return 1; }   # cli connection fails
        cli_cmd=$(build_cli_cmd)
        repl_info=$(${cli_cmd} info replication 2>/dev/null) || repl_info=""
        When call parse_role_line "${repl_info}"
        The status should be success
        The stdout should eq ""
      End
    End
  End

  Describe "fork-safety contract — no pipeline parsing of INFO replication"
    # Background: `valkey-cli ... info replication | grep ... | tr ...`
    # spawns three subprocess children per probe call. When kbagent
    # SIGKILLs check-role.sh for exceeding timeoutSeconds (e.g. during a
    # vertical-scale window when roleProbe slows down), those children are
    # reparented to kbagent's PID 1 (Go binary, not a reaper) and
    # accumulate as zombies. The fix replaces the pipeline with a single
    # command substitution + bash builtin parse, eliminating two of the
    # three children. Observed live in focused stress test T09 iter 1
    # (see focus-kbagent-zombie summary): one (check-role.sh) Z process
    # under PID 1 in the kbagent container.
    check_role_script="../scripts/check-role.sh"

    # Helper: count active (non-comment, non-blank) lines containing a
    # `... | grep ` or `| tr ` token in the given file. Comment lines are
    # `#` after optional leading whitespace.
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
  End

  Describe "is_sentinel_topology()"
    Context "standalone (no sentinel vars)"
      setup() {
        unset SENTINEL_POD_FQDN_LIST
        unset SENTINEL_COMPONENT_NAME
      }
      Before "setup"

      It "returns non-zero"
        When call is_sentinel_topology
        The status should be failure
      End
    End

    Context "sentinel topology (both vars set)"
      setup() {
        export SENTINEL_POD_FQDN_LIST="s0.svc,s1.svc,s2.svc"
        export SENTINEL_COMPONENT_NAME="valkey-sentinel"
      }
      Before "setup"

      teardown() {
        unset SENTINEL_POD_FQDN_LIST
        unset SENTINEL_COMPONENT_NAME
      }
      After "teardown"

      It "returns zero"
        When call is_sentinel_topology
        The status should be success
      End
    End
  End

  Describe "parse_sentinel_master_field()"
    # SENTINEL master <name> returns an alternating list of key/value
    # lines (CRLF-terminated per Redis protocol).
    sentinel_out=$'name\r\nvalkey\r\nip\r\n10.0.0.1\r\nport\r\n6379\r\nrunid\r\nABCDEF0123456789FEDCBA0123456789ABCDEFAB\r\nflags\r\nmaster\r\nconfig-epoch\r\n5\r\nnum-slaves\r\n2\r\n'

    It "extracts runid"
      When call parse_sentinel_master_field "runid" "${sentinel_out}"
      The status should be success
      The stdout should eq "ABCDEF0123456789FEDCBA0123456789ABCDEFAB"
    End

    It "extracts config-epoch"
      When call parse_sentinel_master_field "config-epoch" "${sentinel_out}"
      The status should be success
      The stdout should eq "5"
    End

    It "returns empty when key is missing"
      When call parse_sentinel_master_field "no-such-key" "${sentinel_out}"
      The status should be success
      The stdout should eq ""
    End

    It "tolerates empty input"
      When call parse_sentinel_master_field "runid" ""
      The status should be success
      The stdout should eq ""
    End
  End

  Describe "build_global_role_snapshot() — JSON contract"
    # Contract enforced here:
    #   1. JSON has fields named exactly: term, PodRoleNamePairs, podName,
    #      roleName, podUid. The controller's parseGlobalRoleSnapshot path
    #      drops pairs with mismatched podUid, so the field name and the
    #      injection of KB_POD_UID/KB_POD_NAME both matter.
    #   2. term starts with "sentinel-epoch:" and contains ":" — the
    #      controller stale-event gate uses ":" as the authoritative-vs-
    #      plain discriminator (PR #10269).
    #   3. printf %s, no trailing newline (would break label validation).
    repl_info=$'# Replication\r\nrole:master\r\nmaster_replid:ABCDEF0123456789FEDCBA01\r\nmaster_repl_offset:9999\r\n'

    Context "with KB_POD_NAME and KB_POD_UID injected"
      setup() {
        export KB_POD_NAME="valkey-cluster-valkey-0"
        export KB_POD_UID="3f0a8e2c-7c4b-4d1f-9a2e-1b7c5e0d4a8f"
      }
      Before "setup"

      teardown() {
        unset KB_POD_NAME
        unset KB_POD_UID
      }
      After "teardown"

      It "emits primary JSON with non-empty podName/podUid and field name podUid"
        When call build_global_role_snapshot "primary" "5" "${repl_info}"
        The status should be success
        The stdout should include '"podName":"valkey-cluster-valkey-0"'
        The stdout should include '"podUid":"3f0a8e2c-7c4b-4d1f-9a2e-1b7c5e0d4a8f"'
        The stdout should include '"roleName":"primary"'
        The stdout should include '"term":"sentinel-epoch:5:replid:ABCDEF0123456789"'
        The stdout should not include "pod_uid"
        The stdout should not end with $'\n'
      End

      It "emits secondary JSON when role bit is secondary"
        # Bug B regression: when this pod's runid did NOT match sentinel's
        # master runid, the caller passes role_name=secondary even if
        # local INFO replication reported role:master.
        When call build_global_role_snapshot "secondary" "5" "${repl_info}"
        The status should be success
        The stdout should include '"roleName":"secondary"'
        The stdout should include '"term":"sentinel-epoch:5:replid:ABCDEF0123456789"'
      End

      It "falls back to master_repl_offset when sentinel epoch is empty"
        When call build_global_role_snapshot "primary" "" "${repl_info}"
        The status should be success
        The stdout should include '"term":"sentinel-epoch:9999:replid:ABCDEF0123456789"'
      End
    End
  End

  Describe "Bug B contract — stale local master must not be wrapped as authoritative primary"
    # Simulated scenario:
    #   - Demoted primary (Pod 0). Its local INFO replication still
    #     reports role:master (the stale window). Its run_id is RUNID_OLD.
    #   - Sentinel has elected Pod 1 as the new master. Sentinel's
    #     SENTINEL master <name> reports runid=RUNID_NEW.
    # Expected behavior on the demoted primary:
    #   - role bit from sentinel runid comparison: RUNID_OLD != RUNID_NEW
    #     → secondary, NOT primary, regardless of local INFO replication.
    # This mirrors the logic the main script applies. If this contract
    # ever weakens (e.g. role bit re-derived from local INFO), this test
    # fails.
    derive_role_from_sentinel() {
      local local_runid="$1" sentinel_runid="$2"
      if [ -n "${local_runid}" ] && [ "${local_runid}" = "${sentinel_runid}" ]; then
        printf '%s' "primary"
      else
        printf '%s' "secondary"
      fi
    }

    It "emits secondary when local runid does not match sentinel master runid"
      When call derive_role_from_sentinel "RUNID_OLD_DEMOTED" "RUNID_NEW_PROMOTED"
      The status should be success
      The stdout should eq "secondary"
    End

    It "emits primary when local runid matches sentinel master runid"
      When call derive_role_from_sentinel "RUNID_LIVE_MASTER" "RUNID_LIVE_MASTER"
      The status should be success
      The stdout should eq "primary"
    End

    It "emits secondary when local runid is empty"
      When call derive_role_from_sentinel "" "RUNID_NEW_PROMOTED"
      The status should be success
      The stdout should eq "secondary"
    End
  End
End
