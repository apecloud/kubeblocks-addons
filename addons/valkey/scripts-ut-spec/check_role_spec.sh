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

    Context "primary authority gate via local run_id vs sentinel master runid"
      # During a sentinel-driven failover the deposed primary keeps
      # reporting `role:master` locally for a brief window. Without a
      # cross-check, both the new and the deposed primary would emit
      # `primary <epoch>` with the same config-epoch, and the controller
      # would race-accept both. The fix grounds the role token in
      # Sentinel: only when local INFO=master AND the local run_id
      # matches the Sentinel master `runid` is `primary` authoritative.

      decide_role() {
        local local_role="$1" local_run_id="$2" sentinel_master_runid="$3" engine_version="$4"
        local role_line
        case "${local_role}" in
          master) role_line="role:master" ;;
          slave)  role_line="role:slave"  ;;
          *)      role_line="role:${local_role}" ;;
        esac
        if [ -n "${engine_version}" ] && [ -n "${sentinel_master_runid}" ]; then
          case "${role_line}" in
            "role:master")
              if [ -n "${local_run_id}" ] && [ "${local_run_id}" = "${sentinel_master_runid}" ]; then
                printf '%s\n%s' "primary"   "${engine_version}"
              else
                printf '%s\n%s' "secondary" "${engine_version}"
              fi
              return 0
              ;;
            "role:slave")
              printf '%s\n%s' "secondary" "${engine_version}"
              return 0
              ;;
          esac
        fi
        case "${role_line}" in
          "role:master") printf %s "primary"   ;;
          "role:slave")  printf %s "secondary" ;;
        esac
        return 0
      }

      It "emits primary <epoch> when local INFO=master and run_id matches sentinel master runid"
        When call decide_role "master" "aaaaaaaa" "aaaaaaaa" "5"
        The status should be success
        The stdout should eq "primary
5"
      End

      It "emits secondary <epoch> when local INFO=master but run_id does not match sentinel master runid (round-3 race fix)"
        When call decide_role "master" "aaaaaaaa" "bbbbbbbb" "5"
        The status should be success
        The stdout should eq "secondary
5"
      End

      It "emits secondary <epoch> when local INFO=slave and sentinel reachable"
        When call decide_role "slave" "aaaaaaaa" "bbbbbbbb" "5"
        The status should be success
        The stdout should eq "secondary
5"
      End

      It "falls back to legacy single token when sentinel master runid is empty"
        When call decide_role "master" "aaaaaaaa" "" "5"
        The status should be success
        The stdout should eq "primary"
      End

      It "falls back to legacy single token when sentinel is unreachable (no engine version)"
        When call decide_role "slave" "aaaaaaaa" "" ""
        The status should be success
        The stdout should eq "secondary"
      End

      It "rejects a local master with empty local run_id but a sentinel runid set"
        # Defensive: an empty local run_id cannot prove this Pod is the
        # current master, even if its INFO replication says master.
        When call decide_role "master" "" "aaaaaaaa" "5"
        The status should be success
        The stdout should eq "secondary
5"
      End
    End

    Context "sentinel masters parser extracts both config-epoch and runid"
      # The production script walks the sentinel-masters flat output once
      # and captures both fields; the parser must not depend on field
      # order and must stop after both are found.
      check_role_script="../scripts/check-role.sh"

      It "captures the master runid alongside config-epoch on the script's sentinel response loop"
        When call grep -F 'sentinel_master_runid' "${check_role_script}"
        The status should be success
        The stdout should include "sentinel_master_runid"
      End

      It "reads INFO server for the local run_id"
        When call grep -E 'info[[:space:]]+server' "${check_role_script}"
        The status should be success
        The stdout should include "info server"
      End

      It "rejects non-hex sentinel master runid via case-statement shape guard"
        # Per Edward msg=2140dce9, an empty check alone is not enough:
        # a non-empty but malformed runid (e.g. `not-a-real-runid!`)
        # would otherwise enter the engine-version path. The production
        # path now records the rejection reason in `__drop_reason` so
        # the debug instrumentation can report which sentinel views were
        # excluded; the character-set pattern lives on the right side of
        # the `case` arm.
        When call grep -F '__drop_reason="runid_empty_or_non_hex"' "${check_role_script}"
        The status should be success
        The stdout should include "runid_empty_or_non_hex"
      End
    End

    Context "non-empty malformed sentinel runid is rejected like an empty one"
      # Mirror the production case-statement directly so the decision
      # cell stays pinned: a non-hex runid must be treated the same as
      # empty by the per-sentinel selector, so the script never enters
      # the engine-version path with a malformed authority.
      runid_passes_shape_guard() {
        local runid="$1"
        case "${runid}" in
          ''|*[!0-9a-fA-F]*) printf "REJECT" ;;
          *) printf "ACCEPT" ;;
        esac
      }

      It "accepts a clean lowercase hex runid"
        When call runid_passes_shape_guard "aaaaaaaa1111bbbb2222cccc3333dddd44445555"
        The status should be success
        The stdout should eq "ACCEPT"
      End

      It "accepts a clean uppercase hex runid"
        When call runid_passes_shape_guard "AAAA1111BBBB2222"
        The status should be success
        The stdout should eq "ACCEPT"
      End

      It "rejects empty runid (legacy fallback path)"
        When call runid_passes_shape_guard ""
        The status should be success
        The stdout should eq "REJECT"
      End

      It "rejects non-hex characters (legacy fallback path)"
        When call runid_passes_shape_guard "not-a-real-runid!"
        The status should be success
        The stdout should eq "REJECT"
      End

      It "rejects mixed hex with one stray non-hex char (legacy fallback path)"
        When call runid_passes_shape_guard "abcd1234g"
        The status should be success
        The stdout should eq "REJECT"
      End

      It "rejects runid with embedded whitespace (legacy fallback path)"
        When call runid_passes_shape_guard "abcd 1234"
        The status should be success
        The stdout should eq "REJECT"
      End
    End

    Context "v3 quorum across configured sentinels (Edward+Bob2 sign-off contract)"
      # The roleProbe must not emit `<role> <epoch>` while Sentinels are
      # in a split-view at the same config-epoch. The quorum gate filters
      # each sentinel's response by (uint64 epoch, hex runid, no
      # transient/failure flags), then requires a strict majority of the
      # CONFIGURED sentinel count to fall in a single (epoch, runid)
      # group. Otherwise fall back to legacy single-token output so the
      # controller stays on its EventTime path and the Pod annotation is
      # not advanced to `engine:N` prematurely.

      # Compute strict majority of total configured sentinel count, NOT
      # of reachable/valid count.
      min_valid_for() {
        local total="$1"
        printf "%s" "$(( total / 2 + 1 ))"
      }

      # Encode a list of (epoch, runid, flags) triples (one per sentinel
      # entry, "skip" for unreachable) and decide quorum: emit either
      # `EMIT <epoch>:<runid>` or `LEGACY` plus a diagnostic suffix.
      quorum_decide() {
        local total="$1"; shift
        local min_valid
        min_valid=$(min_valid_for "${total}")
        local entry epoch runid flags
        local -a keys=()
        for entry in "$@"; do
          # skip = unreachable sentinel
          if [ "${entry}" = "skip" ]; then
            continue
          fi
          IFS='|' read -r epoch runid flags <<< "${entry}"
          case "${epoch}" in
            ''|*[!0-9]*) continue ;;
          esac
          case "${runid}" in
            ''|*[!0-9a-fA-F]*) continue ;;
          esac
          case ",${flags}," in
            *,failover_in_progress,*|*,force_failover,*|*,s_down,*|*,o_down,*) continue ;;
          esac
          keys+=("${epoch}:${runid}")
        done
        local valid_count=${#keys[@]}
        if [ "${valid_count}" -lt "${min_valid}" ]; then
          printf "LEGACY"
          return 0
        fi
        local first="${keys[0]}"
        local k
        for k in "${keys[@]}"; do
          if [ "${k}" != "${first}" ]; then
            printf "LEGACY"
            return 0
          fi
        done
        printf "EMIT %s" "${first}"
        return 0
      }

      It "3/3 sentinels agree on a single (epoch, runid) → versioned (pre)"
        When call quorum_decide 3 "16|3119abcd|master" "16|3119abcd|master" "16|3119abcd|master"
        The status should be success
        The stdout should eq "EMIT 16:3119abcd"
      End

      It "3/3 sentinels agree on the converged post-failover view → versioned (post3+)"
        When call quorum_decide 3 "17|00d5beef|master" "17|00d5beef|master" "17|00d5beef|master"
        The status should be success
        The stdout should eq "EMIT 17:00d5beef"
      End

      It "post0 view: 2 old-quorum (epoch16) sentinels + 1 partial new sentinel (empty runid) → versioned on the still-stable OLD quorum"
        # At the very start of the failover, two sentinels still believe
        # the old master at epoch 16, and one has just begun voting for
        # the new master at epoch 17 with the runid not yet filled. The
        # invalid third entry is dropped; the remaining two-of-three
        # quorum still authorities the OLD (epoch, runid) which is the
        # current cluster state. Emitting at this point is safe because
        # the controller's Pod annotation is already at engine:16, so
        # the same-version refresh is a no-op.
        When call quorum_decide 3 "16|3119abcd|master" "16|3119abcd|master" "17||master"
        The status should be success
        The stdout should eq "EMIT 16:3119abcd"
      End

      It "post1/post2 split view: old master with failover_in_progress flag is dropped, two new master views disagree on runid (one empty) → legacy"
        When call quorum_decide 3 "17|3119abcd|master,failover_in_progress,force_failover" "17||master" "17|00d5beef|master"
        The status should be success
        The stdout should eq "LEGACY"
      End

      It "majority of configured (2 of 3) agree, third invalid (empty runid) → versioned"
        When call quorum_decide 3 "17|00d5beef|master" "17|00d5beef|master" "17||master"
        The status should be success
        The stdout should eq "EMIT 17:00d5beef"
      End

      It "majority of configured (2 of 3) agree, third invalid (non-numeric epoch) → versioned"
        When call quorum_decide 3 "17|00d5beef|master" "17|00d5beef|master" "abc|abc|master"
        The status should be success
        The stdout should eq "EMIT 17:00d5beef"
      End

      It "majority of configured (2 of 3) agree, third invalid (failover_in_progress flag) → versioned"
        When call quorum_decide 3 "17|00d5beef|master" "17|00d5beef|master" "17|deadbeef|master,failover_in_progress"
        The status should be success
        The stdout should eq "EMIT 17:00d5beef"
      End

      It "only 1 valid of 3 configured → legacy (single-sentinel cannot self-quorum)"
        When call quorum_decide 3 "17|00d5beef|master" "skip" "skip"
        The status should be success
        The stdout should eq "LEGACY"
      End

      It "2 valid at SAME epoch but DIFFERENT runid → legacy (master identity split)"
        When call quorum_decide 3 "17|00d5beef|master" "17|deadbeef|master" "17||master"
        The status should be success
        The stdout should eq "LEGACY"
      End

      It "2 valid at DIFFERENT epochs → legacy (epoch split)"
        When call quorum_decide 3 "17|00d5beef|master" "16|3119abcd|master" "skip"
        The status should be success
        The stdout should eq "LEGACY"
      End

      It "all 3 sentinels unreachable → legacy"
        When call quorum_decide 3 "skip" "skip" "skip"
        The status should be success
        The stdout should eq "LEGACY"
      End

      It "5-sentinel configured: 3 agree (majority) → versioned even if 2 invalid"
        When call quorum_decide 5 "17|00d5beef|master" "17|00d5beef|master" "17|00d5beef|master" "17||master" "skip"
        The status should be success
        The stdout should eq "EMIT 17:00d5beef"
      End

      It "5-sentinel configured: 2 agree (below majority of 3) → legacy"
        When call quorum_decide 5 "17|00d5beef|master" "17|00d5beef|master" "17||master" "skip" "skip"
        The status should be success
        The stdout should eq "LEGACY"
      End

      It "min_valid is floor(total/2)+1, not ceil(total/2)"
        When call min_valid_for 3
        The status should be success
        The stdout should eq "2"
      End

      It "min_valid for 4 configured is 3 (strict majority)"
        When call min_valid_for 4
        The status should be success
        The stdout should eq "3"
      End

      It "min_valid for 5 configured is 3"
        When call min_valid_for 5
        The status should be success
        The stdout should eq "3"
      End
    End

    Context "v3 grep-level assertions on the production script"
      check_role_script="../scripts/check-role.sh"

      It "computes min_valid as configured_count/2+1"
        When call grep -F 'min_valid=$((configured_count / 2 + 1))' "${check_role_script}"
        The status should be success
        The stdout should include "configured_count"
      End

      It "drops sentinel views with transient/failure flags from quorum"
        When call grep -F 'failover_in_progress' "${check_role_script}"
        The status should be success
        The stdout should include "failover_in_progress"
      End

      It "captures sentinel flags alongside config-epoch and runid"
        When call grep -F 'flags_marker' "${check_role_script}"
        The status should be success
        The stdout should include "flags_marker"
      End

      It "decides primary token from quorum runid match, not local INFO=master"
        # The block that sets authoritative_role must only compare
        # local_run_id with sentinel_master_runid, no role_line check.
        When call grep -A 8 'authoritative_role=""' "${check_role_script}"
        The status should be success
        The stdout should include "sentinel_master_runid"
      End
    End

    Context "VALKEY_CHECK_ROLE_DEBUG diagnostic instrumentation (env-gated)"
      # When the operator sets VALKEY_CHECK_ROLE_DEBUG=1, each call must
      # append one JSON-shaped line to /tmp/check-role-debug.log with the
      # raw per-sentinel readings plus the quorum decision. Stdout MUST
      # stay on the production contract — debug must not leak into the
      # role token under any path.
      check_role_script="../scripts/check-role.sh"

      It "is gated by VALKEY_CHECK_ROLE_DEBUG env (default off)"
        When call grep -F 'VALKEY_CHECK_ROLE_DEBUG' "${check_role_script}"
        The status should be success
        The stdout should include "VALKEY_CHECK_ROLE_DEBUG"
      End

      It "writes the diagnostic record to a Pod-local file under /tmp"
        When call grep -F '__check_role_debug_log="/tmp/check-role-debug.log"' "${check_role_script}"
        The status should be success
        The stdout should include "/tmp/check-role-debug.log"
      End

      It "records both the per-sentinel raw fields and the quorum decision reason"
        # We rely on these names so off-line analysis tooling has a stable
        # contract to grep against.
        When call grep -E '"decision":"|__quorum_decision_reason' "${check_role_script}"
        The status should be success
        The stdout should include "decision"
      End

      It "captures the configured / min_valid / valid counts in the record"
        When call grep -F 'configured_count' "${check_role_script}"
        The status should be success
        The stdout should include "configured_count"
      End

      It "redirects the debug write to /dev/null on failure (won't surface in roleProbe)"
        # Belt-and-braces: the writer must redirect errors so a missing
        # /tmp permission never leaks bytes to stdout that would corrupt
        # the role token.
        When call grep -F '>> "${__check_role_debug_log}" 2>/dev/null || true' "${check_role_script}"
        The status should be success
        The stdout should include "/dev/null"
      End

      It "writes the diagnostic record as a single JSONL line per probe call"
        # Edward msg=be0a283c blocker: per-sentinel objects must be
        # comma-separated in the same line, and the final printf must
        # not embed newlines inside the array literal. Without this,
        # off-line tools cannot split records 1:1 against controller
        # event payloads.
        When call grep -F '"sentinels":[%s]}' "${check_role_script}"
        The status should be success
        The stdout should include "sentinels"
      End

      It "uses a comma separator between per-sentinel array elements"
        When call grep -F '__debug_sep=","' "${check_role_script}"
        The status should be success
        The stdout should include "__debug_sep"
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
