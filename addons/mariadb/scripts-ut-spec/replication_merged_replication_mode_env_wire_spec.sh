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
    helm_template() {
      helm template test "$(chart_path)" "$@" 2>/dev/null
    }

    It "renders an empty-string MARIADB_REPLICATION_MODE when replication.mode is unset"
      When call helm_template
      The status should be success
      The output should include 'name: MARIADB_REPLICATION_MODE
            value: ""'
    End

    It "renders MARIADB_REPLICATION_MODE=semisync when --set replication.mode=semisync"
      When call helm_template --set replication.mode=semisync
      The status should be success
      The output should include 'name: MARIADB_REPLICATION_MODE
            value: "semisync"'
    End

    It "renders MARIADB_REPLICATION_MODE=async when --set replication.mode=async"
      When call helm_template --set replication.mode=async
      The status should be success
      The output should include 'name: MARIADB_REPLICATION_MODE
            value: "async"'
    End
  End

  Describe "Helm template-time fail-closed on invalid value (Jack B2 fix)"
    # alpha.89 v1 commit 13 v2 (Helen 2026-05-20, Jack B2 fix msg
    # `f9433634`) — invalid `replication.mode` values fail the helm
    # render with a clear error BEFORE the manifest is produced, so
    # the bad value never lands in the rendered CmpD env. Catches
    # the diagnosis at install/upgrade time, not container startup.
    helm_template_or_fail() {
      helm template test "$(chart_path)" "$@" 2>&1
    }

    It "rejects mariadb.replication.mode=bogus at render time"
      When call helm_template_or_fail --set replication.mode=bogus
      The status should be failure
      The output should include 'invalid mariadb.replication.mode'
      The output should include 'bogus'
      The output should include 'expected one of'
    End

    It "rejects arbitrary string values at render time"
      When call helm_template_or_fail --set replication.mode=garbage
      The status should be failure
      The output should include 'invalid mariadb.replication.mode'
      The output should include 'garbage'
    End

    It "rejects mixed-case async at render time (only lowercase enum members accepted)"
      When call helm_template_or_fail --set replication.mode=ASYNC
      The status should be failure
      The output should include 'invalid mariadb.replication.mode'
    End

    It "accepts the empty string explicitly (preserves default behavior)"
      When call helm_template_or_fail --set replication.mode=""
      The status should be success
      The output should include 'name: MARIADB_REPLICATION_MODE
            value: ""'
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
