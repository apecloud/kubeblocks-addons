# shellcheck shell=sh

Describe "mariadb backup ActionSet account contract"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  actionset_path() {
    printf "%s/addons/mariadb/templates/actionset.yaml" "$(repo_root)"
  }

  bpt_path() {
    printf "%s/addons/mariadb/templates/backuppolicytemplate.yaml" "$(repo_root)"
  }

  semisync_cmpd_path() {
    printf "%s/addons/mariadb/scripts/replication-entrypoint.sh" "$(repo_root)"
  }

  replication_merged_cmpd_path() {
    printf "%s/addons/mariadb/scripts/replication-entrypoint.sh" "$(repo_root)"
  }

  remote_internal_admin_grants_backup_required_privileges() {
    grep -qF "GRANT RELOAD, PROCESS ON *.* TO '\${user}'@'%';" "$(semisync_cmpd_path)" &&
      grep -qF "GRANT RELOAD, PROCESS ON *.* TO '\${user}'@'%';" "$(replication_merged_cmpd_path)"
  }

  selected_account_paths_use_backup_account() {
    awk '
      /mariadb --host="\$\{DP_DB_HOST\}" --user="\$\{BACKUP_DB_USER\}" --password="\$\{BACKUP_DB_PASSWORD\}"/ {
        probe_count++
      }
      /mariadb-backup --backup --slave-info --stream=mbstream --host=\$\{DP_DB_HOST\}/ {
        in_backup=1
      }
      in_backup && /--user=\$\{BACKUP_DB_USER\} --password=\$\{BACKUP_DB_PASSWORD\}/ {
        backup_uses_selected=1
      }
      END {
        exit !(probe_count >= 2 && backup_uses_selected)
      }
    ' "$(actionset_path)"
  }

  It "uses a backup execution account separate from the DP target account when an internal account is available"
    When call grep -qF 'BACKUP_DB_USER="${MARIADB_INTERNAL_ROOT_USER}"' "$(actionset_path)"
    The status should be success
  End

  It "falls back to the DP target account when no internal account is exposed"
    When call grep -qF 'BACKUP_DB_USER="${DP_DB_USER}"' "$(actionset_path)"
    The status should be success
  End

  It "uses the selected backup execution account for the connection probe, privilege gate, and mariadb-backup"
    When call selected_account_paths_use_backup_account
    The status should be success
  End

  It "fails closed when the backup privilege gate never becomes ready"
    When call grep -qF 'Backup privileges not available after ${max_attempts}s' "$(actionset_path)"
    The status should be success
    The contents of file "$(actionset_path)" should not include "proceeding anyway"
    The contents of file "$(actionset_path)" should include "return 1"
  End

  It "grants the remote internal backup account the mariabackup-required RELOAD and PROCESS privileges"
    When call remote_internal_admin_grants_backup_required_privileges
    The status should be success
  End

  It "documents that target.account is only the DP-selected target secret, not necessarily the runtime SQL execution account"
    When call grep -qF 'ActionSet may switch to the chart-managed' "$(bpt_path)"
    The status should be success
  End

End
