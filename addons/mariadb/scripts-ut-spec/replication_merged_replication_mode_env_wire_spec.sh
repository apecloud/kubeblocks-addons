# shellcheck shell=sh

# alpha.89 v1 commit 13 (Helen 2026-05-20, C3 design env plumbing —
# Helm value / Option C path).
#
# Lock the wire-up that connects `mariadb.replication.mode` (Helm
# value) → `MARIADB_REPLICATION_MODE` (env var on the merged CmpD's
# mariadb container) → `apply_replication_mode_mapping` (mapper
# sourced by `reconfigureAction.persisted`).
#
# This commit deliberately uses the Helm value path rather than KB
# ParametersDefinition or Cluster annotations: the standard
# parameters reconfigure path is blocked by the `replicationmode?: _|_`
# CUE backstop (commit 11 v2) so a user-supplied `replicationMode`
# parameter cannot reach the engine via the normal reconfigure flow.
# Helm-install-time setting is the conservative plumbing path that
# does not depend on speculative KB behavior. Runtime mode flip via
# OpsRequest reconfigure is deferred to a future commit.
#
# Strategy: render the merged CmpD via `helm template` and grep the
# rendered manifest for the expected env declarations and default
# values; render again with `--set replication.mode=semisync` /
# `--set replication.mode=async` to verify the value flows through.

Describe "alpha.89 commit 13 — replication.mode Helm value → MARIADB_REPLICATION_MODE env wire"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/mariadb" "$(repo_root)"
  }

  values_path() {
    printf "%s/addons/mariadb/values.yaml" "$(repo_root)"
  }

  cmpd_merged_path() {
    printf "%s/addons/mariadb/templates/cmpd-replication-merged.yaml" "$(repo_root)"
  }

  Describe "values.yaml declares replication.mode with empty default"
    It "declares a top-level replication block"
      When call grep -E '^replication:' "$(values_path)"
      The status should be success
      The output should include "replication:"
    End

    It "declares replication.mode with empty-string default to preserve existing behavior"
      # 2-space-indented `mode: ""` under `replication:` — the empty
      # string is the default so existing clusters (whose values do
      # not set this) see no behavioral change.
      When call awk '/^replication:/{in_block=1; next} in_block && /^[A-Za-z]/{in_block=0} in_block && /^[[:space:]]+mode:[[:space:]]*""/{print "ok"; exit}' "$(values_path)"
      The output should equal "ok"
    End
  End

  Describe "cmpd-replication-merged.yaml wires MARIADB_REPLICATION_MODE env from Helm value"
    It "declares a MARIADB_REPLICATION_MODE env entry in the merged CmpD"
      When call grep -c 'name: MARIADB_REPLICATION_MODE' "$(cmpd_merged_path)"
      The status should be success
      The output should equal "1"
    End

    It "sources the env value through the mariadb.replication.mode.validate helper (Jack B2 fail-closed path)"
      When call grep -c 'include "mariadb\.replication\.mode\.validate"' "$(cmpd_merged_path)"
      The status should be success
      The output should equal "1"
    End

    helper_path() {
      printf "%s/addons/mariadb/templates/_helpers.tpl" "$(repo_root)"
    }

    It "_helpers.tpl declares the mariadb.replication.mode.validate helper"
      When call grep -c 'define "mariadb\.replication\.mode\.validate"' "$(helper_path)"
      The status should be success
      The output should equal "1"
    End

    It "validator defaults the value to empty string when Helm value is unset"
      When call grep -c '\.Values\.replication\.mode | default ""' "$(helper_path)"
      The status should be success
      The output should equal "1"
    End

    It "validator uses fail to abort helm render on invalid value"
      When call grep -c 'fail (printf "invalid mariadb\.replication\.mode' "$(helper_path)"
      The status should be success
      The output should equal "1"
    End
  End

  Describe "rendered manifest reflects the Helm value"
    # alpha.89 v1 commit 13 v3 v2 (Helen 2026-05-20, Jack
    # test-harness HOLD msg `ea4b77ee`) — earlier form passed the
    # full ~16k-line `helm template` output into `When call ... The
    # output should include ...`. ShellSpec's matcher loads the
    # entire captured stdout into memory and pattern-matches against
    # it, which is slow / unstable on macOS+Homebrew bash and timed
    # out at Jack's 34s budget. Refactor: render once into a tmp
    # file in a helper, then use `grep` on the file (Jack's
    # `awk/rg` suggestion applied via `grep -F` for fixed-string
    # matching). `When call grep ...` captures only the matched
    # line, not the full manifest, so the matcher stays bounded.

    render_to_tmp() {
      # Render the chart to a tmp file and echo the path. Caller
      # consumes via grep. `helm template` stderr is silenced for
      # the positive cases; the fail-closed describe uses a
      # separate helper that captures stderr.
      tmp_render=$(mktemp -t mariadb-render-XXXXXX)
      helm template test "$(chart_path)" "$@" >"${tmp_render}" 2>/dev/null
      printf "%s" "${tmp_render}"
    }

    cleanup_tmp_render() {
      [ -n "${tmp_render:-}" ] && rm -f "${tmp_render}" 2>/dev/null || true
    }

    AfterEach 'cleanup_tmp_render'

    grep_env_value_after() {
      # Look for the literal two-line shape:
      #   - name: MARIADB_REPLICATION_MODE
      #     value: "<expected>"
      # Use grep -A1 + awk so we only capture the relevant 2 lines
      # rather than the whole manifest. Returns 0 on match, 1 on
      # miss.
      file_path="$1"
      expected_value="$2"
      grep -F -A1 'name: MARIADB_REPLICATION_MODE' "${file_path}" |
        awk -v want="value: \"${expected_value}\"" '
          NR==1 { next }
          $0 ~ "value: " && index($0, want) { print "ok"; exit }
        '
    }

    It "renders an empty-string MARIADB_REPLICATION_MODE when replication.mode is unset"
      tmp_render=$(render_to_tmp)
      When call grep_env_value_after "${tmp_render}" ""
      The status should be success
      The output should equal "ok"
    End

    It "renders MARIADB_REPLICATION_MODE=semisync when --set replication.mode=semisync"
      tmp_render=$(render_to_tmp --set replication.mode=semisync)
      When call grep_env_value_after "${tmp_render}" "semisync"
      The status should be success
      The output should equal "ok"
    End

    It "renders MARIADB_REPLICATION_MODE=async when --set replication.mode=async"
      tmp_render=$(render_to_tmp --set replication.mode=async)
      When call grep_env_value_after "${tmp_render}" "async"
      The status should be success
      The output should equal "ok"
    End
  End

  Describe "Helm template-time fail-closed on invalid value (Jack B2 fix)"
    # alpha.89 v1 commit 13 v2 (Helen 2026-05-20) — invalid
    # `replication.mode` values fail the helm render BEFORE any
    # manifest is produced. v3 v2 (Jack test-harness HOLD msg
    # `ea4b77ee`) — same refactor: capture stderr to a tmp file
    # and grep -c, never feed the full output into a ShellSpec
    # matcher.

    render_stderr_to_tmp() {
      tmp_stderr=$(mktemp -t mariadb-rend-err-XXXXXX)
      helm template test "$(chart_path)" "$@" >/dev/null 2>"${tmp_stderr}"
      printf "%s|%s" "$?" "${tmp_stderr}"
    }

    cleanup_tmp_stderr() {
      [ -n "${tmp_stderr:-}" ] && rm -f "${tmp_stderr}" 2>/dev/null || true
    }

    AfterEach 'cleanup_tmp_stderr'

    check_render_failed_with_sentinel() {
      rc_and_path="$1"
      expected_value_in_msg="$2"
      rc="${rc_and_path%%|*}"
      file_path="${rc_and_path#*|}"
      if [ "${rc}" = "0" ]; then
        echo "expected non-zero rc but got 0" >&2
        return 1
      fi
      if ! grep -qF "invalid mariadb.replication.mode" "${file_path}"; then
        echo "expected stderr to contain 'invalid mariadb.replication.mode'" >&2
        return 1
      fi
      if ! grep -qF "${expected_value_in_msg}" "${file_path}"; then
        echo "expected stderr to contain '${expected_value_in_msg}'" >&2
        return 1
      fi
      printf "ok"
    }

    It "rejects mariadb.replication.mode=bogus at render time"
      tmp_stderr_setup=$(render_stderr_to_tmp --set replication.mode=bogus)
      tmp_stderr="${tmp_stderr_setup#*|}"
      When call check_render_failed_with_sentinel "${tmp_stderr_setup}" "bogus"
      The status should be success
      The output should equal "ok"
    End

    It "rejects arbitrary string values at render time"
      tmp_stderr_setup=$(render_stderr_to_tmp --set replication.mode=garbage)
      tmp_stderr="${tmp_stderr_setup#*|}"
      When call check_render_failed_with_sentinel "${tmp_stderr_setup}" "garbage"
      The status should be success
      The output should equal "ok"
    End

    It "rejects mixed-case async at render time (only lowercase enum members accepted)"
      tmp_stderr_setup=$(render_stderr_to_tmp --set replication.mode=ASYNC)
      tmp_stderr="${tmp_stderr_setup#*|}"
      When call check_render_failed_with_sentinel "${tmp_stderr_setup}" "ASYNC"
      The status should be success
      The output should equal "ok"
    End

    It "accepts the empty string explicitly (preserves default behavior)"
      # Empty-string render should succeed; reuse the render_to_tmp
      # helper from the previous Describe via inline duplicate.
      tmp_render=$(mktemp -t mariadb-render-empty-XXXXXX)
      helm template test "$(chart_path)" --set replication.mode="" >"${tmp_render}" 2>/dev/null
      render_rc=$?
      grep_result=$(grep -F -A1 'name: MARIADB_REPLICATION_MODE' "${tmp_render}" |
        awk 'NR==2 && $0 ~ /value: ""/ { print "ok"; exit }')
      rm -f "${tmp_render}" 2>/dev/null || true
      When call test "${render_rc}" -eq 0 -a "${grep_result}" = "ok"
      The status should be success
    End
  End

  Describe "non-merged topologies do NOT receive the env var"
    # The Helm value flows ONLY into the merged CmpD's container env
    # (where the persisted reconfigureAction sources the mapper).
    # Standalone / galera topologies do not have the merged
    # reconfigureAction.persisted helper wired with the mapper call,
    # so adding the env there would be dead.

    cmpd_standalone_path() {
      printf "%s/addons/mariadb/templates/cmpd.yaml" "$(repo_root)"
    }

    cmpd_galera_path() {
      printf "%s/addons/mariadb/templates/cmpd-galera.yaml" "$(repo_root)"
    }

    It "standalone cmpd.yaml does NOT declare MARIADB_REPLICATION_MODE env"
      When call grep -c 'name: MARIADB_REPLICATION_MODE' "$(cmpd_standalone_path)"
      The status should be failure
      The output should equal "0"
    End

    It "galera cmpd-galera.yaml does NOT declare MARIADB_REPLICATION_MODE env"
      When call grep -c 'name: MARIADB_REPLICATION_MODE' "$(cmpd_galera_path)"
      The status should be failure
      The output should equal "0"
    End
  End

End
