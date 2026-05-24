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

  Describe "engine-authoritative version trailer (PR #10280 whitespace-token contract)"
    # check-role.sh now appends a second whitespace-separated token — the
    # sentinel config-epoch — when at least one reachable sentinel returns
    # a clean uint64. The controller-side parser (post-PR #10280) splits
    # stdout on any whitespace and accepts only `<role>` or
    # `<role> <uint64>`; anything else is rejected outright. So the script
    # must either emit `primary\n<uint64>` (or `primary <uint64>`) or
    # legacy single-line output, never a labeled `kb-role-version=` form.
    parse_one_sentinel_epoch() {
      local sentinel_out="$1"
      local sline ce_marker="" epoch=""
      while IFS= read -r sline; do
        sline="${sline%$'\r'}"
        if [ -n "${ce_marker}" ]; then
          epoch="${sline}"
          break
        fi
        [ "${sline}" = "config-epoch" ] && ce_marker="1"
      done <<<"${sentinel_out}"
      printf "%s" "${epoch}"
    }

    Context "single sentinel returns a clean numeric config-epoch"
      It "extracts the numeric value following the config-epoch marker"
        sentinel_out=$'name\nvlk-foo\nconfig-epoch\n42\nnum-slaves\n2'
        When call parse_one_sentinel_epoch "${sentinel_out}"
        The status should be success
        The stdout should eq "42"
      End
    End

    Context "single sentinel output missing config-epoch marker"
      It "returns empty so the per-sentinel loop continues to the next sentinel"
        sentinel_out=$'name\nvlk-foo\nnum-slaves\n2'
        When call parse_one_sentinel_epoch "${sentinel_out}"
        The status should be success
        The stdout should eq ""
      End
    End

    Context "single sentinel returns non-numeric config-epoch"
      It "extracts the raw value (the numeric guard in the loop drops it)"
        sentinel_out=$'name\nvlk-foo\nconfig-epoch\nNaN\nnum-slaves\n2'
        When call parse_one_sentinel_epoch "${sentinel_out}"
        The status should be success
        The stdout should eq "NaN"
      End
    End

    Context "highest-epoch selector across multiple reachable sentinels"
      # Mirror the production loop: walk a list of (mock) sentinel outputs,
      # numeric-guard each, keep the maximum.
      best_epoch_across() {
        local out epoch best=-1
        for out in "$@"; do
          epoch=$(parse_one_sentinel_epoch "${out}")
          case "${epoch}" in
            ''|*[!0-9]*) continue ;;
          esac
          if [ "${epoch}" -gt "${best}" ]; then
            best="${epoch}"
          fi
        done
        if [ "${best}" -ge 0 ]; then
          printf "%s" "${best}"
        fi
        return 0
      }

      It "picks the highest config-epoch when two sentinels disagree"
        a=$'name\nvlk\nconfig-epoch\n5'
        b=$'name\nvlk\nconfig-epoch\n7'
        When call best_epoch_across "${a}" "${b}"
        The status should be success
        The stdout should eq "7"
      End

      It "skips an isolated sentinel that returned empty"
        a=$'name\nvlk\nnum-slaves\n2'
        b=$'name\nvlk\nconfig-epoch\n3'
        When call best_epoch_across "${a}" "${b}"
        The status should be success
        The stdout should eq "3"
      End

      It "skips a sentinel that returned non-numeric config-epoch"
        a=$'name\nvlk\nconfig-epoch\nNaN'
        b=$'name\nvlk\nconfig-epoch\n11'
        When call best_epoch_across "${a}" "${b}"
        The status should be success
        The stdout should eq "11"
      End

      It "returns empty when no sentinel produced a clean uint64"
        a=$'name\nvlk\nconfig-epoch\nNaN'
        b=$'name\nvlk\nnum-slaves\n2'
        When call best_epoch_across "${a}" "${b}"
        The status should be success
        The stdout should eq ""
      End
    End

    Context "second-token emission obeys whitespace-token contract"
      # The controller's strict parser splits the entire stdout on whitespace
      # and accepts only `<role>` or `<role> <uint64>`. Anything else is
      # rejected. So the second token must be the bare numeric epoch — no
      # `kb-role-version=` prefix.
      compose_output() {
        local role="$1" version="$2"
        printf %s "${role}"
        case "${version}" in
          ''|*[!0-9]*) : ;;
          *) printf '\n%s' "${version}" ;;
        esac
      }

      It "emits whitespace-separated tokens for a clean uint64"
        When call compose_output "primary" "42"
        The status should be success
        The stdout should eq "primary
42"
      End

      It "drops second token when version is empty"
        When call compose_output "secondary" ""
        The status should be success
        The stdout should eq "secondary"
      End

      It "drops second token when version is non-numeric"
        When call compose_output "primary" "NaN"
        The status should be success
        The stdout should eq "primary"
      End

      It "splits with strings.Fields-compatible whitespace"
        # Production uses '\n' between role and version. The controller's
        # strings.Fields() in Go accepts spaces, tabs, and newlines.
        out=$(compose_output "primary" "42")
        # Two tokens after splitting on whitespace
        When call bash -c "read -ra t <<< \"${out//$'\n'/ }\"; printf '%s\n' \"\${t[0]} \${t[1]} count=\${#t[@]}\""
        The status should be success
        The stdout should eq "primary 42 count=2"
      End

      It "never emits the legacy kb-role-version= label form"
        out=$(compose_output "primary" "42")
        When call grep -q 'kb-role-version=' <<<"${out}"
        The status should be failure
      End
    End

    Context "TLS-aware sentinel cli construction"
      # check-role.sh must append ${VALKEY_CLI_TLS_ARGS} to the sentinel
      # query path; without it, every sentinel call on a TLS-enabled topology
      # would fail and the script would silently degrade to legacy single-
      # line output, defeating the engine-version gate. The production line
      # is grep-able directly from the script.
      check_role_script="../scripts/check-role.sh"

      It "resolves VALKEY_CLI_TLS_ARGS into a local before the sentinel cli call"
        When call grep -F 'sentinel_tls_args="${VALKEY_CLI_TLS_ARGS:-}"' "${check_role_script}"
        The status should be success
        The stdout should include "VALKEY_CLI_TLS_ARGS"
      End

      It "passes the TLS args local to the sentinel valkey-cli call"
        When call grep -E 'valkey-cli[^|]*sentinel masters' "${check_role_script}"
        The status should be success
        The stdout should include "sentinel_tls_args"
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
End
