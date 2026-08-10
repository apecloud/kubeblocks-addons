# shellcheck shell=bash

Describe "PostgreSQL boolean parameter schema"
  pg_bool_pattern() {
    local constraint="../config/pg18-config-constraint.cue"

    awk -F'"' '/^#PgBool: string & =~"/ { print $2; exit }' "$constraint"
  }

  pg_bool_accepts() {
    local value="$1"
    local pattern

    pattern="$(pg_bool_pattern)"
    pattern="${pattern#(?i)}"
    printf '%s\n' "$value" | grep -Eiq "$pattern"
  }

  assert_pg_bool_accepts() {
    local value

    for value in \
      t tr tru true \
      f fa fal fals false \
      y ye yes n no on of off \
      0 1 TRUE FALSE; do
      pg_bool_accepts "$value" || return 1
    done
  }

  assert_pg_bool_rejects() {
    local value

    for value in "" o " true" "false " truth enabled 2 00; do
      if pg_bool_accepts "$value"; then
        return 1
      fi
    done
  }

  assert_pg_bool_contract() {
    local major="$1"
    local constraint="../config/pg${major}-config-constraint.cue"
    local template="../config/pg${major}-config.tpl"

    grep -Fq '#PgBool: string & =~"(?i)^(t(r(u(e)?)?)?|f(a(l(s(e)?)?)?)?|y(e(s)?)?|n(o)?|on|of(f)?|0|1)$"' "$constraint"
    ! grep -Eq '^#PgBool:.*\bbool\b' "$constraint"
    grep -Fq 'wal_init_zero?: #PgBool' "$constraint"
    grep -Fq 'autovacuum?: #PgBool' "$constraint"
    grep -Fq 'fsync: #PgBool | *"true"' "$constraint"
    ! grep -Ev '^#PgBool:' "$constraint" | grep -Eq ':\s*bool\b|bool\s*&\s*false'
    ! grep -Eq '#PgBool \| \*(true|false)' "$constraint"
    grep -Fq 'huge_pages?: string & "on" | "off" | "try"' "$constraint"
    grep -Fq '"pgtle.enable_password_check"?: string & "on" | "off" | "require"' "$constraint"
    grep -Fq "cron.log_statement = 'on'" "$template"
    if [ "$major" -eq 13 ]; then
      ! grep -Fq "index_adviser.enable_log" "$template"
    else
      grep -Fq "index_adviser.enable_log = 'on'" "$template"
    fi
    grep -Fq "wal_init_zero = off" "$template"

    if [ "$major" -ge 14 ]; then
      grep -Fq "remove_temp_files_after_crash = 'on'" "$template"
    fi
  }

  assert_force_parallel_mode_contract() {
    local major="$1"
    local constraint="../config/pg${major}-config-constraint.cue"
    local template="../config/pg${major}-config.tpl"

	if [ "$major" -eq 13 ]; then
	  grep -Fq 'force_parallel_mode?: string & =~"(?i)^(off|on|regress|true|false|1|0)$"' "$constraint"
	else
	  grep -Fq 'force_parallel_mode?: string & =~"(?i)^(off|on|regress)$"' "$constraint"
	fi
    grep -Fq "force_parallel_mode = 'off'" "$template"
  }

  It "keeps pg12 boolean settings on the shared PostgreSQL boolean contract"
    When call assert_pg_bool_contract 12
    The status should be success
  End

  It "keeps pg13 boolean settings on the shared PostgreSQL boolean contract"
    When call assert_pg_bool_contract 13
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

  It "accepts PostgreSQL boolean spellings and unambiguous prefixes"
    When call assert_pg_bool_accepts
    The status should be success
  End

  It "rejects ambiguous, padded, and invalid boolean spellings"
    When call assert_pg_bool_rejects
    The status should be success
  End

  It "models PostgreSQL 12 force_parallel_mode as an enum"
    When call assert_force_parallel_mode_contract 12
    The status should be success
  End

  It "models PostgreSQL 13 force_parallel_mode as an enum"
    When call assert_force_parallel_mode_contract 13
    The status should be success
  End

  It "models PostgreSQL 14 force_parallel_mode as an enum"
    When call assert_force_parallel_mode_contract 14
    The status should be success
  End

  It "models PostgreSQL 15 force_parallel_mode as an enum"
    When call assert_force_parallel_mode_contract 15
    The status should be success
  End
End
