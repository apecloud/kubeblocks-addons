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

  Describe "engine-authoritative kb-role-version trailer (PR #10280 contract)"
    # check-role.sh now appends a second line `kb-role-version=<sentinel
    # config-epoch>` when sentinel is reachable and returns a clean uint64.
    # The controller-side strict parser rejects malformed `kb-role-version=`
    # lines outright, so the script either emits a well-formed numeric line
    # or no version line at all (legacy mode).
    parse_engine_version() {
      local sentinel_out="$1"
      local sline ce_marker="" engine_version=""
      while IFS= read -r sline; do
        sline="${sline%$'\r'}"
        if [ -n "${ce_marker}" ]; then
          engine_version="${sline}"
          break
        fi
        [ "${sline}" = "config-epoch" ] && ce_marker="1"
      done <<<"${sentinel_out}"
      printf "%s" "${engine_version}"
    }

    Context "sentinel returns a clean numeric config-epoch"
      It "extracts the numeric value following the config-epoch marker"
        sentinel_out=$'name\nvlk-foo\nconfig-epoch\n42\nnum-slaves\n2'
        When call parse_engine_version "${sentinel_out}"
        The status should be success
        The stdout should eq "42"
      End
    End

    Context "sentinel output missing config-epoch marker"
      It "returns empty so the script falls back to legacy single-line output"
        sentinel_out=$'name\nvlk-foo\nnum-slaves\n2'
        When call parse_engine_version "${sentinel_out}"
        The status should be success
        The stdout should eq ""
      End
    End

    Context "sentinel returns non-numeric config-epoch (malformed)"
      It "extracts the raw value (numeric guard later drops non-uint64)"
        sentinel_out=$'name\nvlk-foo\nconfig-epoch\nNaN\nnum-slaves\n2'
        When call parse_engine_version "${sentinel_out}"
        The status should be success
        The stdout should eq "NaN"
      End
    End

    Context "numeric guard before emitting second line"
      # Mirror the production check that drops anything not purely numeric
      # so the controller's strict parser never sees a malformed value.
      emit_or_drop() {
        local v="$1"
        case "${v}" in
          ''|*[!0-9]*) printf "DROP" ;;
          *) printf "kb-role-version=%s" "${v}" ;;
        esac
      }

      It "emits the line for a clean uint64"
        When call emit_or_drop "42"
        The status should be success
        The stdout should eq "kb-role-version=42"
      End

      It "drops empty value"
        When call emit_or_drop ""
        The status should be success
        The stdout should eq "DROP"
      End

      It "drops non-numeric value"
        When call emit_or_drop "NaN"
        The status should be success
        The stdout should eq "DROP"
      End

      It "drops mixed alphanumeric"
        When call emit_or_drop "42abc"
        The status should be success
        The stdout should eq "DROP"
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
