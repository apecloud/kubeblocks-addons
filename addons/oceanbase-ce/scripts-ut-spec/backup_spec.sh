# shellcheck shell=bash

Describe "OceanBase CE backup SQL timeout scope"
  backup_script="../dataprotection/backup.sh"

  count_timeout_prefixed_sql() {
    local statement="$1"
    grep -Ec "SET SESSION ob_query_timeout=1000000000;[[:space:]]*ALTER SYSTEM SET ${statement}" "$backup_script" || true
  }

  It "raises the session timeout for LOG_ARCHIVE_DEST"
    When call count_timeout_prefixed_sql 'LOG_ARCHIVE_DEST='
    The output should eq "1"
  End

  It "does not broaden the timeout change to LOG_ARCHIVE_DEST_STATE"
    When call count_timeout_prefixed_sql "LOG_ARCHIVE_DEST_STATE='ENABLE'"
    The output should eq "0"
  End

  It "does not broaden the timeout change to DATA_BACKUP_DEST"
    When call count_timeout_prefixed_sql 'DATA_BACKUP_DEST='
    The output should eq "0"
  End
End
