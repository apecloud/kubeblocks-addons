# shellcheck shell=sh

Describe "MariaDB incremental and binlog backup resources"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  template_dir() {
    printf "%s/addons/mariadb/templates" "$(repo_root)"
  }

  dataprotection_dir() {
    printf "%s/addons/mariadb/dataprotection" "$(repo_root)"
  }

  It "defines a native MariaDB incremental ActionSet"
    The contents of file "$(template_dir)/actionset-incremental.yaml" should include "backupType: Incremental"
    The contents of file "$(template_dir)/actionset-incremental.yaml" should include "mariadb-incremental-backup.sh"
    The contents of file "$(dataprotection_dir)/mariadb-incremental-backup.sh" should include 'mariadb-backup --backup --slave-info --stream=mbstream'
    The contents of file "$(dataprotection_dir)/mariadb-incremental-backup.sh" should include '--incremental-basedir="$PARENT_DIR"'
  End

  It "restores the complete incremental ancestor chain"
    The contents of file "$(dataprotection_dir)/mariadb-incremental-restore.sh" should include 'DP_BASE_BACKUP_NAME'
    The contents of file "$(dataprotection_dir)/mariadb-incremental-restore.sh" should include 'DP_ANCESTOR_INCREMENTAL_BACKUP_NAMES'
    The contents of file "$(dataprotection_dir)/mariadb-incremental-restore.sh" should include '--incremental-dir='
    The contents of file "$(dataprotection_dir)/mariadb-incremental-restore.sh" should include 'mariadb-backup --copy-back'
  End

  It "defines continuous primary binlog archive and PITR replay"
    The contents of file "$(template_dir)/actionset-pitr.yaml" should include "backupType: Continuous"
    The contents of file "$(template_dir)/backuppolicytemplate.yaml" should include "name: archive-binlog"
    The contents of file "$(template_dir)/backuppolicytemplate.yaml" should include "role: primary"
    The contents of file "$(dataprotection_dir)/mariadb-pitr-backup.sh" should include "datasafed push -z zstd-fastest"
    The contents of file "$(dataprotection_dir)/mariadb-pitr-restore.sh" should include "mariadb-binlog"
    The contents of file "$(dataprotection_dir)/mariadb-pitr-restore.sh" should include "DP_RESTORE_TIME"
    The contents of file "$(dataprotection_dir)/mariadb-pitr-restore.sh" should include ".kb-pitr-binlog-info"
    The contents of file "$(dataprotection_dir)/mariadb-pitr-restore.sh" should include '--start-position="$anchor_gtid"'
    The contents of file "$(dataprotection_dir)/mariadb-pitr-restore.sh" should include "--skip-gtid-strict-mode"
    The contents of file "$(dataprotection_dir)/mariadb-pitr-restore.sh" should include "sed '/SET @@session\\.gtid_seq_no=/d'"
  End

  It "enables ROW binlogs on every topology"
    The contents of file "$(repo_root)/addons/mariadb/config/mariadb-standalone.tpl" should include "log_bin = /var/lib/mysql/binlog/mariadb-bin"
    The contents of file "$(repo_root)/addons/mariadb/config/mariadb-galera.tpl" should include "log_bin = /var/lib/mysql/binlog/mariadb-bin"
    The contents of file "$(repo_root)/addons/mariadb/config/mariadb-replication.tpl" should include "log_bin = /var/lib/mysql/binlog/mariadb-bin"
    The contents of file "$(repo_root)/addons/mariadb/scripts/galera-start.sh" should include '--server-id=$((10#${POD_NAME##*-} + 1))'
  End

End
