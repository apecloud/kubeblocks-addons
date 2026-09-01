# shellcheck shell=sh

Describe "dataprotection/pgdump-restore.sh"

  script_path() {
    printf "%s" "../dataprotection/pgdump-restore.sh"
  }

  setup() {
    tmpdir=$(mktemp -d -t pg-dump-restore-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"
    rm -f /tmp/pg_restore.log
    DP_DATASAFED_BIN_PATH="${bindir}"
    DP_BACKUP_BASE_PATH="/backup"
    DP_BACKUP_NAME="backup-test"
    POSTGRES_PASSWORD="secret"
    POSTGRES_USER="postgres"
    DP_DB_HOST="localhost"
    DP_DB_PORT="5432"
    BACKUP_DIR="${tmpdir}/restore-workdir"
    export PATH CALL_LOG DP_DATASAFED_BIN_PATH DP_BACKUP_BASE_PATH \
      DP_BACKUP_NAME POSTGRES_PASSWORD POSTGRES_USER DP_DB_HOST DP_DB_PORT BACKUP_DIR
    unset PG_RESTORE_EXIT PG_RESTORE_STDERR jobs database schemas tables \
      schema_only conflict_policy 2>/dev/null || true
    write_stubs
  }

  cleanup() {
    rm -rf "${tmpdir}"
    rm -f /tmp/pg_restore.log
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  write_stubs() {
    cat > "${bindir}/datasafed" <<'EOF'
#!/bin/sh
printf 'datasafed %s\n' "$*" >> "${CALL_LOG}"
printf '%s\n' "-- dump data"
EOF
    cat > "${bindir}/tar" <<'EOF'
#!/bin/sh
printf 'tar %s\n' "$*" >> "${CALL_LOG}"
cat > /dev/null
EOF
    cat > "${bindir}/psql" <<'EOF'
#!/bin/sh
printf 'psql %s\n' "$*" >> "${CALL_LOG}"
exit 0
EOF
    cat > "${bindir}/pg_restore" <<'EOF'
#!/bin/sh
printf 'pg_restore %s\n' "$*" >> "${CALL_LOG}"
if [ -n "${PG_RESTORE_STDERR:-}" ]; then
  printf '%s\n' "${PG_RESTORE_STDERR}" >&2
fi
exit "${PG_RESTORE_EXIT:-0}"
EOF
    chmod +x "${bindir}/datasafed" "${bindir}/tar" "${bindir}/psql" "${bindir}/pg_restore"
  }

  call_log() {
    cat "${CALL_LOG}"
  }

  It "restores successfully when pg_restore succeeds"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "parameters:"
    The result of function call_log should include "pg_restore"
  End

  It "fails when the ignored-errors warning has no error details"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR="pg_restore: warning: errors ignored on restore: 3"
    When run bash "$(script_path)"
    The status should be failure
    The output should include "parameters:"
    The error should include "errors ignored on restore"
  End

  It "treats existing-object errors as success under the default CONTINUE policy"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR='pg_restore: error: could not execute query: ERROR: relation "items" already exists
pg_restore: warning: errors ignored on restore: 1'
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "treating as success under conflict_policy=CONTINUE"
    The error should include "already exists"
  End

  It "fails on duplicate-key COPY errors under the default CONTINUE policy"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR='pg_restore: error: COPY failed for table "items": ERROR: duplicate key value violates unique constraint "items_pkey"
pg_restore: warning: errors ignored on restore: 1'
    When run bash "$(script_path)"
    The status should be failure
    The output should include "parameters:"
    The error should include "duplicate key value violates unique constraint"
  End

  It "cleans and restores the requested database under the DROP policy"
    export database="app"
    export conflict_policy="DROP"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "-d app --clean --if-exists"
    The output should not include "-C"
    The result of function call_log should include "pg_restore -h localhost -U postgres -p 5432 -j 4 -Fd -v --no-owner --no-privileges -d app --clean --if-exists"
    The result of function call_log should not include "pg_restore -h localhost -U postgres -p 5432 -j 4 -Fd -v -d postgres"
  End

  It "propagates ignored-error failures when conflict_policy is FAIL"
    export conflict_policy="FAIL"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR="pg_restore: warning: errors ignored on restore: 3"
    When run bash "$(script_path)"
    The status should be failure
    The output should include "--exit-on-error"
    The output should include "-C"
    The output should include "-d postgres"
    The error should include "errors ignored on restore"
  End

  It "fails when pg_restore fails without the ignored-errors warning"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR="pg_restore: error: could not connect to server"
    When run bash "$(script_path)"
    The status should be failure
    The output should include "parameters:"
    The error should include "could not connect"
  End
End
