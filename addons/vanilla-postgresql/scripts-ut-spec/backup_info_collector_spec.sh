# shellcheck shell=bash

Describe 'backup info collector script'
  Include ../dataprotection/backup-info-collector.sh

  # Mock psql command
  psql() {
    echo "2024-01-15 10:00:00+00"
  }

  # Mock datasafed command
  datasafed() {
    if [ "$1" = "stat" ]; then
      echo "TotalSize 1024"
    fi
  }

  setup() {
    # Setup environment variables
    export DP_DATASAFED_BIN_PATH="/usr/local/bin"
    export DP_BACKUP_BASE_PATH="/backup"
    export DP_BACKUP_INFO_FILE="/tmp/backup_info"

    # Clean up any existing files
    touch "${DP_BACKUP_INFO_FILE}"
  }

  clean() {
    rm -f "${DP_BACKUP_INFO_FILE}"
  }

  Describe 'get_current_time()'
    It 'returns current time from database'
      When call get_current_time
      The output should equal "2024-01-15 10:00:00+00"
    End
  End

  Describe 'stat_and_save_backup_info()'
    BeforeEach 'setup'

    AfterEach 'clean'

    Mock date
      time="$2"
      echo "${time:0:10}T${time:11:8}Z"
    End

    It 'creates backup info file with correct format'
      When call stat_and_save_backup_info "2024-01-15 09:00:00" "2024-01-15 10:00:00"
      The file "${DP_BACKUP_INFO_FILE}" should be exist
      The contents of file "${DP_BACKUP_INFO_FILE}" should include '"totalSize":"1024"'
      The contents of file "${DP_BACKUP_INFO_FILE}" should include '"start":"2024-01-15T09:00:00Z"'
      The contents of file "${DP_BACKUP_INFO_FILE}" should include '"end":"2024-01-15T10:00:00Z"'
    End

    It 'uses current time when stop time is not provided'
      When call stat_and_save_backup_info "2024-01-15 09:00:00"
      The file "${DP_BACKUP_INFO_FILE}" should be exist
      The contents of file "${DP_BACKUP_INFO_FILE}" should include '"start":"2024-01-15T09:00:00Z"'
      The contents of file "${DP_BACKUP_INFO_FILE}" should include '"end":"2024-01-15T10:00:00Z"'
    End
  End

  Describe 'handle_exit()'
    BeforeEach 'setup'

    AfterEach 'clean'

    It 'does not create exit file when exit code is zero'
      # Set $? to 0
      true
      When call handle_exit
      The file "${DP_BACKUP_INFO_FILE}.exit" should not be exist
      The status should be success
    End
  End
End