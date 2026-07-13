# shellcheck shell=sh

Describe "DoltDB replication backup and restore support"
  chart_path="../Chart.yaml"
  backup_policy_template="../templates/backuppolicytemplate.yaml"
  helpers_template="../templates/_helpers.tpl"
  actionset_template="../templates/actionset.yaml"
  backup_pre_script="../dataprotection/backup-pre.sh"
  restore_post_script="../dataprotection/restore-post.sh"
  role_probe_script="../scripts/doltdb-role-probe.sh"
  examples_dir="../../../examples/doltdb"

  setup() {
    ORIGINAL_PATH="$PATH"
    TEST_DIR="$(mktemp -d)"
    export ORIGINAL_PATH TEST_DIR
    export PATH="${TEST_DIR}:$PATH"
  }
  BeforeEach "setup"

  cleanup() {
    export PATH="$ORIGINAL_PATH"
    rm -rf "$TEST_DIR"
    unset ORIGINAL_PATH TEST_DIR DOLT_ROOT_PASSWORD DATA_DIR DOLT_REPLICATION_RESTORE
  }
  AfterEach "cleanup"

  assert_role_probe_kubeblocks_version_contract() {
    grep -Fq 'addon.kubeblocks.io/kubeblocks-version: ">=1.1.0-beta.7"' "$chart_path" || return 1
    grep -Fq "printf '%s %s\\n'" "$role_probe_script" || return 1
  }

  assert_replication_backup_policy_contract() {
    grep -Fq 'define "doltdb.replicationBackupPolicyTemplate"' "$helpers_template" || return 1
    grep -Fq 'name: {{ include "doltdb.replicationBackupPolicyTemplate" . }}' "$backup_policy_template" || return 1
    grep -Fq '{{ include "doltdb.replicationCmpdRegexpPattern" . }}' "$backup_policy_template" || return 1
    grep -Fq 'role: primary' "$backup_policy_template" || return 1
    grep -Fq 'account: root' "$backup_policy_template" || return 1
    grep -Fq 'name: DOLT_REPLICATION_RESTORE' "$backup_policy_template" || return 1
    grep -Fq 'value: "true"' "$backup_policy_template" || return 1
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

  backup_pre_fails_when_database_listing_sql_fails() {
    mkdir -p "${TEST_DIR}/data"
    cat >"${TEST_DIR}/dolt" <<'EOF'
#!/bin/sh
echo "authentication failed" >&2
exit 7
EOF
    chmod +x "${TEST_DIR}/dolt"

    DATA_DIR="${TEST_DIR}/data" DOLT_ROOT_PASSWORD="root-password" bash "$backup_pre_script"
  }

  prepare_restore_staging() {
    mkdir -p "${TEST_DIR}/data/.kb-doltdb-restore/current/repos/appdb"
    printf 'appdb\trepos/appdb\n' >"${TEST_DIR}/data/.kb-doltdb-restore/current/manifest.tsv"
  }

  restore_post_skips_replication_status_by_default() {
    prepare_restore_staging
    cat >"${TEST_DIR}/dolt" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${TEST_DIR}/dolt-argv"
for arg do
  case "$arg" in
    --query=*dolt_cluster.dolt_cluster_status*)
      echo "cluster status should not be queried for standalone restore" >&2
      exit 9
      ;;
    --query=*) exit 0 ;;
  esac
done
exit 0
EOF
    chmod +x "${TEST_DIR}/dolt"

    DATA_DIR="${TEST_DIR}/data" DOLT_ROOT_PASSWORD="root-password" bash "$restore_post_script"
  }

  restore_post_fails_when_replication_status_query_fails() {
    prepare_restore_staging
    cat >"${TEST_DIR}/dolt" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${TEST_DIR}/dolt-argv"
for arg do
  case "$arg" in
    --query=*dolt_cluster.dolt_cluster_status*)
      echo "network timeout" >&2
      exit 9
      ;;
    --query=*) exit 0 ;;
  esac
done
exit 0
EOF
    chmod +x "${TEST_DIR}/dolt"

    DATA_DIR="${TEST_DIR}/data" DOLT_ROOT_PASSWORD="root-password" DOLT_REPLICATION_RESTORE="true" bash "$restore_post_script"
  }

  It "declares a minimum KubeBlocks version for two-token roleProbe output"
    When call assert_role_probe_kubeblocks_version_contract
    The status should be success
  End

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

  It "fails backup instead of uploading an empty archive when database listing fails"
    When call backup_pre_fails_when_database_listing_sql_fails
    The status should be failure
    The error should include "authentication failed"
    The error should include "failed to list Dolt databases"
  End

  It "does not require cluster status for standalone post-ready restore"
    When call restore_post_skips_replication_status_by_default
    The status should be success
    The output should include "restoring Dolt database appdb"
    The contents of file "${TEST_DIR}/dolt-argv" should not include "dolt_cluster.dolt_cluster_status"
  End

  It "fails replication post-ready restore when primary status cannot be queried"
    When call restore_post_fails_when_replication_status_query_fails
    The status should be failure
    The output should include "restoring Dolt database appdb"
    The error should include "network timeout"
    The error should include "failed to query Dolt cluster role for appdb"
  End
End
