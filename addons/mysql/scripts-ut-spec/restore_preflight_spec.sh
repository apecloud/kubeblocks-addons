# shellcheck shell=bash

Describe "xtrabackup restore preflight"
  setup() {
    export __SOURCED__=1
    export DATA_DIR="${SHELLSPEC_TMPBASE}/mysql-data"
    rm -rf "$DATA_DIR"
  }
  Before "setup"

  Describe "full restore"
    Include ../dataprotection/restore.sh

    It "allows an empty target"
      When call restore_preflight
      The status should be success
    End

    It "treats a completion marker as an idempotent retry"
      mkdir -p "$DATA_DIR"
      touch "$DATA_DIR/.xtrabackup_restore"
      When call restore_preflight
      The status should equal 10
      The output should include "already completed"
    End

    It "fails closed on partial restored data"
      mkdir -p "$DATA_DIR/mysql"
      When call restore_preflight
      The status should be failure
      The stderr should include "non-empty without completion marker"
    End

    It "ignores a filesystem lost+found directory"
      mkdir -p "$DATA_DIR/lost+found"
      When call restore_preflight
      The status should be success
    End
  End
End
