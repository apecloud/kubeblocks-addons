# shellcheck shell=bash

Describe "PostgreSQL wal_compression configuration"
  assert_pg15_plus_wal_compression_contract() {
    local major="$1"

    grep -Fq 'wal_compression: string & (*"pglz" | "lz4" | "zstd" | "on" | "off" | "True" | "False" | "true" | "false")' "../config/pg${major}-config-constraint.cue"
    grep -Fq "wal_compression = 'pglz'" "../config/pg${major}-config.tpl"
  }

  It "keeps pg15 wal_compression aligned with PostgreSQL enum values"
    When call assert_pg15_plus_wal_compression_contract 15
    The status should be success
  End

  It "keeps pg16 wal_compression aligned with PostgreSQL enum values"
    When call assert_pg15_plus_wal_compression_contract 16
    The status should be success
  End

  It "keeps pg17 wal_compression aligned with PostgreSQL enum values"
    When call assert_pg15_plus_wal_compression_contract 17
    The status should be success
  End

  It "keeps pg18 wal_compression aligned with PostgreSQL enum values"
    When call assert_pg15_plus_wal_compression_contract 18
    The status should be success
  End
End
