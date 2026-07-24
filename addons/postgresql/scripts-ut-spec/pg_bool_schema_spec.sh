# shellcheck shell=bash

Describe "PostgreSQL boolean parameter schema"
  assert_pg_bool_contract() {
    local major="$1"
    local constraint="../config/pg${major}-config-constraint.cue"
    local template="../config/pg${major}-config.tpl"

    grep -Fq '#PgBool: string & =~"(?i)^(on|off|true|false|yes|no|0|1)$"' "$constraint"
    ! grep -Eq '^#PgBool:.*\bbool\b' "$constraint"
    grep -Fq 'wal_init_zero?: #PgBool' "$constraint"
    grep -Fq 'autovacuum?: #PgBool' "$constraint"
    grep -Fq 'fsync: #PgBool | *"true"' "$constraint"
    ! grep -Ev '^#PgBool:' "$constraint" | grep -Eq ':\s*bool\b|bool\s*&\s*false'
    ! grep -Eq '#PgBool \| \*(true|false)' "$constraint"
    grep -Fq 'huge_pages?: string & "on" | "off" | "try"' "$constraint"
    grep -Fq '"pgtle.enable_password_check"?: string & "on" | "off" | "require"' "$constraint"
    grep -Fq "cron.log_statement = 'on'" "$template"
    grep -Fq "index_adviser.enable_log = 'on'" "$template"
    grep -Fq "wal_init_zero = off" "$template"

    if [ "$major" != "12" ]; then
      grep -Fq "remove_temp_files_after_crash = 'on'" "$template"
    fi
  }

  It "keeps pg12 boolean settings on the shared PostgreSQL boolean contract"
    When call assert_pg_bool_contract 12
    The status should be success
  End

  It "keeps pg14 boolean settings on the shared PostgreSQL boolean contract"
    When call assert_pg_bool_contract 14
    The status should be success
  End

  It "keeps pg15 boolean settings on the shared PostgreSQL boolean contract"
    When call assert_pg_bool_contract 15
    The status should be success
  End

  It "keeps pg16 boolean settings on the shared PostgreSQL boolean contract"
    When call assert_pg_bool_contract 16
    The status should be success
  End

  It "keeps pg17 boolean settings on the shared PostgreSQL boolean contract"
    When call assert_pg_bool_contract 17
    The status should be success
  End

  It "keeps pg18 boolean settings on the shared PostgreSQL boolean contract"
    When call assert_pg_bool_contract 18
    The status should be success
  End
End
