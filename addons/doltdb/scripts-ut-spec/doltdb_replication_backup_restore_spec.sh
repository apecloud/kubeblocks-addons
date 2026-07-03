# shellcheck shell=sh

Describe "DoltDB replication backup and restore support"
  backup_policy_template="../templates/backuppolicytemplate.yaml"
  helpers_template="../templates/_helpers.tpl"
  actionset_template="../templates/actionset.yaml"
  backup_pre_script="../dataprotection/backup-pre.sh"
  restore_post_script="../dataprotection/restore-post.sh"
  examples_dir="../../../examples/doltdb"

  assert_replication_backup_policy_contract() {
    grep -Fq 'define "doltdb.replicationBackupPolicyTemplate"' "$helpers_template" || return 1
    grep -Fq 'name: {{ include "doltdb.replicationBackupPolicyTemplate" . }}' "$backup_policy_template" || return 1
    grep -Fq '{{ include "doltdb.replicationCmpdRegexpPattern" . }}' "$backup_policy_template" || return 1
    grep -Fq 'role: primary' "$backup_policy_template" || return 1
    grep -Fq 'account: root' "$backup_policy_template" || return 1
  }

  assert_backup_pre_lists_databases_from_sql() {
    grep -Fq 'SHOW DATABASES;' "$backup_pre_script" || return 1
    grep -Fq 'list_databases()' "$backup_pre_script" || return 1
    grep -Fq 'while IFS= read -r db_name; do' "$backup_pre_script" || return 1
  }

  assert_actionset_uses_remote_sql_jobs() {
    grep -Fq 'DP_DB_HOST' "$backup_pre_script" || return 1
    grep -Fq 'DP_DB_PASSWORD' "$backup_pre_script" || return 1
    grep -Fq 'DP_DB_HOST' "$restore_post_script" || return 1
    grep -Fq 'DP_DB_PASSWORD' "$restore_post_script" || return 1
    grep -Fq 'dolt_cluster.dolt_cluster_status' "$restore_post_script" || return 1
    grep -Fq "CALL DOLT_COMMIT('--allow-empty'" "$restore_post_script" || return 1
    grep -Fq '{{- .Files.Get "dataprotection/backup-pre.sh" | nindent 10 }}' "$actionset_template" || return 1
    ! grep -Fq 'preBackup:' "$actionset_template" || return 1
    ! grep -Fq '      - exec:' "$actionset_template" || return 1
  }

  assert_replication_examples_contract() {
    [ -f "${examples_dir}/backup-replication.yaml" ] || return 1
    [ -f "${examples_dir}/restore-replication.yaml" ] || return 1
    [ ! -f "${examples_dir}/restore-action.yaml" ] || return 1
    [ ! -f "${examples_dir}/restore-replication-action.yaml" ] || return 1
    [ -f "${examples_dir}/switchover.yaml" ] || return 1
    [ -f "${examples_dir}/restart-replication.yaml" ] || return 1
    grep -Fq 'topology: replication' "${examples_dir}/cluster-replication.yaml" || return 1
    grep -Fq 'backupPolicyName: doltdb-replication-doltdb-backup-policy' "${examples_dir}/backup-replication.yaml" || return 1
    grep -Fq 'restore:' "${examples_dir}/restore.yaml" || return 1
    grep -Fq 'restore:' "${examples_dir}/restore-replication.yaml" || return 1
    grep -Fq 'name: doltdb-cluster-backup' "${examples_dir}/restore.yaml" || return 1
    grep -Fq 'name: doltdb-replication-backup' "${examples_dir}/restore-replication.yaml" || return 1
    grep -Fq 'dataprotection.kubeblocks.io/source-target-name: doltdb' "${examples_dir}/restore.yaml" || return 1
    grep -Fq 'dataprotection.kubeblocks.io/source-target-name: doltdb' "${examples_dir}/restore-replication.yaml" || return 1
    grep -Fq 'type: Switchover' "${examples_dir}/switchover.yaml" || return 1
    grep -Fq 'candidateName: doltdb-replication-doltdb-1' "${examples_dir}/switchover.yaml" || return 1
    grep -Fq 'type: Restart' "${examples_dir}/restart-replication.yaml" || return 1
    grep -Fq 'Automatic failover and failback are not supported' "${examples_dir}/README.md" || return 1
    grep -Fq 'Restore replication' "${examples_dir}/README.md" || return 1
  }

  It "renders a replication backup policy targeting the current primary"
    When call assert_replication_backup_policy_contract
    The status should be success
  End

  It "enumerates current databases through SQL before backing up each Dolt database"
    When call assert_backup_pre_lists_databases_from_sql
    The status should be success
  End

  It "uses remote Dolt client SQL from DataProtection jobs instead of target pod exec"
    When call assert_actionset_uses_remote_sql_jobs
    The status should be success
  End

  It "documents replication backup, restore, switchover, and restart examples"
    When call assert_replication_examples_contract
    The status should be success
  End
End
