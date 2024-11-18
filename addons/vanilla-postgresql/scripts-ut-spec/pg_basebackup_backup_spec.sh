# shellcheck shell=bash

Describe 'backup script'
  Include ../dataprotection/backup-info-collector.sh

  setup() {
    # Mock environment variables
    export DP_BACKUP_INFO_FILE="/tmp/backup_info"
    touch "${DP_BACKUP_INFO_FILE}"
  }

  clean() {
    rm -f "${DP_BACKUP_INFO_FILE}"
  }

  BeforeEach 'setup'

  AfterEach 'clean'

  Describe 'backup process'
    Mock pg_basebackup
      echo "backup data"
    End

    Mock datasafed
      case "$1" in
        "push")
          echo "pushing backup data"
          ;;
        "stat")
          echo "TotalSize 1024"
          ;;
      esac
    End

    Mock date
      echo "2024-01-01T10:00:00Z"
    End

    Mock psql
      echo "2024-01-15 10:00:00+00"
    End

    It 'creates backup info file'
      When run source ../dataprotection/pg-basebackup-backup.sh
      The file "$DP_BACKUP_INFO_FILE" should be exist
      The stdout should include "pushing backup data"
      The contents of file "$DP_BACKUP_INFO_FILE" should include "totalSize"
      The contents of file "$DP_BACKUP_INFO_FILE" should include "2024-01-01T10:00:00Z"
    End
  End
End