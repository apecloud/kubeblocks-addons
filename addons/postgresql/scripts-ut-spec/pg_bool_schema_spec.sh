# shellcheck shell=bash

Describe "PostgreSQL boolean parameter schema"
  pg_bool_pattern() {
    local constraint="../config/pg13-config-constraint.cue"

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
    local constraint="../config/pg13-config-constraint.cue"
    local template="../config/pg13-config.tpl"

    grep -Fq '#PgBool: string & =~"(?i)^(t(r(u(e)?)?)?|f(a(l(s(e)?)?)?)?|y(e(s)?)?|n(o)?|on|of(f)?|0|1)$"' "$constraint" || return 1
    ! grep -Eq '^#PgBool:.*\bbool\b' "$constraint" || return 1
    grep -Fq 'wal_init_zero?: #PgBool' "$constraint" || return 1
    grep -Fq 'autovacuum?: #PgBool' "$constraint" || return 1
    grep -Fq 'fsync: #PgBool | *"true"' "$constraint" || return 1
    ! grep -Ev '^#PgBool:' "$constraint" | grep -Eq ':\s*bool\b|bool\s*&\s*false' || return 1
    ! grep -Eq '#PgBool \| \*(true|false)' "$constraint" || return 1
    grep -Fq 'huge_pages?: string & "on" | "off" | "try"' "$constraint" || return 1
    grep -Fq '"pgtle.enable_password_check"?: string & "on" | "off" | "require"' "$constraint" || return 1
    grep -Fq "cron.log_statement = 'on'" "$template" || return 1
    ! grep -Fq "index_adviser.enable_log" "$template" || return 1
    grep -Fq "wal_init_zero = off" "$template"
  }

  assert_force_parallel_mode_contract() {
    local constraint="../config/pg13-config-constraint.cue"
    local template="../config/pg13-config.tpl"

    grep -Fq 'force_parallel_mode?: string & =~"(?i)^(off|on|regress|true|false|1|0)$"' "$constraint" || return 1
    grep -Fq "force_parallel_mode = 'off'" "$template"
  }

  It "keeps pg13 boolean settings on the shared PostgreSQL boolean contract"
    When call assert_pg_bool_contract
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

  It "models PostgreSQL 13 force_parallel_mode as an enum"
    When call assert_force_parallel_mode_contract
    The status should be success
  End

End
