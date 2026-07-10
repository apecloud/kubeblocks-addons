# shellcheck shell=bash

Describe "PostgreSQL wal_init_zero configuration"
  assert_wal_init_zero_contract() {
    local major="$1"

    grep -Fq 'wal_init_zero?: (bool & (false | true)) | (string & ("on" | "off"))' "../config/pg${major}-config-constraint.cue"
    grep -Fq 'wal_init_zero = off' "../config/pg${major}-config.tpl"
  }

  It "keeps pg12 wal_init_zero compatible with bool and PostgreSQL on/off values"
    When call assert_wal_init_zero_contract 12
    The status should be success
  End

  It "keeps pg14 wal_init_zero compatible with bool and PostgreSQL on/off values"
    When call assert_wal_init_zero_contract 14
    The status should be success
  End

  It "keeps pg15 wal_init_zero compatible with bool and PostgreSQL on/off values"
    When call assert_wal_init_zero_contract 15
    The status should be success
  End

  It "keeps pg16 wal_init_zero compatible with bool and PostgreSQL on/off values"
    When call assert_wal_init_zero_contract 16
    The status should be success
  End

  It "keeps pg17 wal_init_zero compatible with bool and PostgreSQL on/off values"
    When call assert_wal_init_zero_contract 17
    The status should be success
  End

  It "keeps pg18 wal_init_zero compatible with bool and PostgreSQL on/off values"
    When call assert_wal_init_zero_contract 18
    The status should be success
  End
End
