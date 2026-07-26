# shellcheck shell=bash

Describe "MySQL PITR master-binlog purge boundary"
  Include ../dataprotection/mysql-pitr-binlog-purge.sh

  It "purges only the oldest file when six files are fully protected"
    protected="mysql-bin.000001 mysql-bin.000002 mysql-bin.000003 mysql-bin.000004 mysql-bin.000005 mysql-bin.000006"

    When call select_mysql_binlog_purge_target "$protected" "$protected" 5 \
      mysql-bin.000001 mysql-bin.000002 mysql-bin.000003 \
      mysql-bin.000004 mysql-bin.000005 mysql-bin.000006
    The status should be success
    The output should equal "mysql-bin.000002"
  End

  It "stops before the first unsynced or unuploaded gap"
    synced="mysql-bin.000001 mysql-bin.000002 mysql-bin.000003 mysql-bin.000004 mysql-bin.000005 mysql-bin.000006 mysql-bin.000007 mysql-bin.000008"
    uploaded="mysql-bin.000001 mysql-bin.000002 mysql-bin.000004 mysql-bin.000005 mysql-bin.000006 mysql-bin.000007 mysql-bin.000008"

    When call select_mysql_binlog_purge_target "$synced" "$uploaded" 5 \
      mysql-bin.000001 mysql-bin.000002 mysql-bin.000003 mysql-bin.000004 \
      mysql-bin.000005 mysql-bin.000006 mysql-bin.000007 mysql-bin.000008
    The status should be success
    The output should equal "mysql-bin.000003"
  End

  It "refuses to purge when the first file is not protected"
    When call select_mysql_binlog_purge_target \
      "mysql-bin.000002" "mysql-bin.000002" 1 \
      mysql-bin.000001 mysql-bin.000002
    The status should be failure
    The output should be blank
  End

  It "refuses to purge when only the protected tail remains"
    protected="mysql-bin.000001 mysql-bin.000002 mysql-bin.000003"

    When call select_mysql_binlog_purge_target "$protected" "$protected" 5 \
      mysql-bin.000001 mysql-bin.000002 mysql-bin.000003
    The status should be failure
    The output should be blank
  End
End
