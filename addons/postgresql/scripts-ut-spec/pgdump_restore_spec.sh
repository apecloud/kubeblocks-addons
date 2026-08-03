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
    unset DATASAFED_LIST_OUT DATASAFED_PULL_EXIT PG_RESTORE_EXIT PG_RESTORE_STDERR \
      jobs database schemas tables schema_only conflict_policy 2>/dev/null || true
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
cmd="$1"
case "$cmd" in
  list) printf '%s\n' "${DATASAFED_LIST_OUT:-}" ;;
  pull)
    if [ "${DATASAFED_PULL_EXIT:-0}" -ne 0 ]; then
      exit "${DATASAFED_PULL_EXIT}"
    fi
    printf '%s\n' "-- dump data"
    ;;
esac
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

  It "fails loudly when the backup file does not exist in the repository"
    export DATASAFED_LIST_OUT=""
    When run bash "$(script_path)"
    The status should be failure
    The error should include "backup-test.tar not found"
    The result of function call_log should not include "pg_restore"
  End

  It "restores successfully when the backup exists and pg_restore succeeds"
    export DATASAFED_LIST_OUT="backup-test.tar"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "parameters:"
    The result of function call_log should include "pg_restore"
  End

  It "treats ignored per-object errors as success under the default CONTINUE policy"
    export DATASAFED_LIST_OUT="backup-test.tar"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR="pg_restore: warning: errors ignored on restore: 3"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "treating as success under conflict_policy=CONTINUE"
    The error should include "errors ignored on restore"
  End

  It "propagates ignored-error failures when conflict_policy is FAIL"
    export DATASAFED_LIST_OUT="backup-test.tar"
    export conflict_policy="FAIL"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR="pg_restore: warning: errors ignored on restore: 3"
    When run bash "$(script_path)"
    The status should be failure
    The output should include "--exit-on-error"
    The error should include "errors ignored on restore"
  End

  It "fails when pg_restore fails without the ignored-errors warning"
    export DATASAFED_LIST_OUT="backup-test.tar"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR="pg_restore: error: could not connect to server"
    When run bash "$(script_path)"
    The status should be failure
    The output should include "parameters:"
    The error should include "could not connect"
  End

  It "fails when datasafed pull fails mid-stream"
    export DATASAFED_LIST_OUT="backup-test.tar"
    export DATASAFED_PULL_EXIT=1
    When run bash "$(script_path)"
    The status should be failure
    The result of function call_log should not include "pg_restore"
  End
End
