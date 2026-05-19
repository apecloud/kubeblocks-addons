# shellcheck shell=sh

# alpha.89 v1 commit 8 (Helen 2026-05-19, C1 path default-async
# closure) — the merged CmpD's spec.configs[].template must point
# at the async-default ConfigMap template
# (`mariadb-replication-config-template` -> `config/mariadb-replication.tpl`),
# not the semisync template inherited from the scaffolding commit.
# Default cluster behavior is async; semisync is opt-in via the
# four `rpl_semi_sync_*` parameters validated by the PD CUE schema
# in commit 3 v2.
#
# This spec locks the template pointer + the corresponding
# my.cnf content so a future edit cannot silently flip the default
# back to semisync.

Describe "alpha.89 merged CmpD default-async ConfigMap template"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  cmpd_path() {
    printf "%s/addons/mariadb/templates/cmpd-replication-merged.yaml" "$(repo_root)"
  }

  async_tpl_path() {
    printf "%s/addons/mariadb/config/mariadb-replication.tpl" "$(repo_root)"
  }

  cmpd_configs_template() {
    awk '
      /^[[:space:]]+configs:[[:space:]]*$/ { in_configs=1; next }
      in_configs && /^[[:space:]]+template:[[:space:]]+/ {
        sub(/^[[:space:]]+template:[[:space:]]+/, "", $0)
        sub(/[[:space:]]+$/, "", $0)
        print $0
        exit
      }
    ' "$(cmpd_path)"
  }

  It "the merged CmpD's spec.configs[].template references the async ConfigMap template"
    When call cmpd_configs_template
    The output should equal "mariadb-replication-config-template"
  End

  It "the merged CmpD does NOT reference the semisync ConfigMap template"
    # If a future edit accidentally flips back to
    # mariadb-semisync-config-template, the default behavior
    # silently becomes semisync without surfacing in any test.
    When call grep -qF 'template: mariadb-semisync-config-template' "$(cmpd_path)"
    The status should be failure
  End

  Describe "async template my.cnf content"
    It "does not set rpl_semi_sync_master_enabled in defaults"
      # The async template should omit the four semisync engine
      # variables so engine defaults (OFF/0) take effect. If a
      # future edit adds them with `= ON`, this spec fails.
      When call grep -E '^[[:space:]]*rpl_semi_sync_master_enabled[[:space:]]*=[[:space:]]*ON' "$(async_tpl_path)"
      The status should be failure
    End

    It "does not set rpl_semi_sync_slave_enabled = ON in defaults"
      When call grep -E '^[[:space:]]*rpl_semi_sync_slave_enabled[[:space:]]*=[[:space:]]*ON' "$(async_tpl_path)"
      The status should be failure
    End
  End

End
