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
    printf "%s/addons/mariadb/templates/cmpd-replication.yaml" "$(repo_root)"
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

  Describe "merged CmpD runtime semisync guard"
    entrypoint_path() {
      printf "%s/addons/mariadb/scripts/replication-entrypoint.sh" "$(repo_root)"
    }

    It "declares the MARIADB_REPLICATION_MODE based semisync env helper before primary listener exposure"
      helper_line=$(grep -n 'is_semisync_mode_env() {' "$(entrypoint_path)" | cut -d: -f1)
      expose_line=$(grep -n 'expose_sql_listener_for_primary_role() {' "$(entrypoint_path)" | cut -d: -f1)
      test -n "${helper_line}" && test -n "${expose_line}" && test "${helper_line}" -lt "${expose_line}"
    End

    It "routes primary listener semisync reset through the guarded helper"
      count=$(grep -c 'reset_semisync_master_ack_receiver_if_enabled "primary-' "$(entrypoint_path)")
      The variable count should equal 2
    End

    It "background ACK receiver reset is guarded by is_semisync_mode_env"
      awk '
        /label=background-tcp-probe/ { found_log=1 }
        /if is_semisync_mode_env; then/ { in_guard=1 }
        in_guard && /SET GLOBAL rpl_semi_sync_master_enabled=0; SET GLOBAL rpl_semi_sync_master_enabled=1;/ { found_guarded=1 }
        END { exit !(found_log && found_guarded) }
      ' "$(entrypoint_path)"
    End
  End

End
