# shellcheck shell=sh

Describe "dataprotection/pgdumpall-restore.sh"

  script_path() {
    printf "%s" "../dataprotection/pgdumpall-restore.sh"
  }

  setup() {
    tmpdir=$(mktemp -d -t pg-dumpall-restore-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"
    DP_DATASAFED_BIN_PATH="${bindir}"
    DP_BACKUP_BASE_PATH="/backup"
    DP_BACKUP_NAME="backup-test"
    DP_DB_PASSWORD="secret"
    DP_DB_USER="postgres"
    DP_DB_HOST="localhost"
    DP_DB_PORT="5432"
    export PATH CALL_LOG DP_DATASAFED_BIN_PATH DP_BACKUP_BASE_PATH \
      DP_BACKUP_NAME DP_DB_PASSWORD DP_DB_USER DP_DB_HOST DP_DB_PORT
    unset DATASAFED_LIST_OUT DATASAFED_PULL_EXIT PSQL_EXIT PSQL_STDERR PSQL_STDERR_FILE 2>/dev/null || true
    write_stubs
  }

  cleanup() {
    rm -rf "${tmpdir}"
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
    cat > "${bindir}/psql" <<'EOF'
#!/bin/sh
printf 'psql %s\n' "$*" >> "${CALL_LOG}"
cat > /dev/null
if [ -n "${PSQL_STDERR_FILE:-}" ]; then
  cat "${PSQL_STDERR_FILE}" >&2
elif [ -n "${PSQL_STDERR:-}" ]; then
  printf '%s\n' "${PSQL_STDERR}" >&2
fi
exit "${PSQL_EXIT:-0}"
EOF
    chmod +x "${bindir}/datasafed" "${bindir}/psql"
  }

  call_log() {
    cat "${CALL_LOG}"
  }

  It "fails loudly when the backup file does not exist in the repository"
    export DATASAFED_LIST_OUT=""
    When run bash "$(script_path)"
    The status should be failure
    The error should include "backup-test.sql.zst not found"
    The result of function call_log should not include "psql"
  End

  It "restores and reports success when the backup file exists"
    export DATASAFED_LIST_OUT="backup-test.sql.zst"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "restore complete!"
    The result of function call_log should include "datasafed pull"
    The result of function call_log should include "psql"
  End

  It "fails when psql fails to apply the dump"
    export DATASAFED_LIST_OUT="backup-test.sql.zst"
    export PSQL_EXIT=2
    When run bash "$(script_path)"
    The status should be failure
    The error should include "pgdumpall restore pipeline failed"
    The output should not include "restore complete!"
  End

  It "fails when datasafed pull fails mid-stream"
    export DATASAFED_LIST_OUT="backup-test.sql.zst"
    export DATASAFED_PULL_EXIT=1
    When run bash "$(script_path)"
    The status should be failure
    The error should include "pgdumpall restore pipeline failed"
    The output should not include "restore complete!"
  End

  It "allows all addon-provisioned role already-exists conflicts"
    export DATASAFED_LIST_OUT="backup-test.sql.zst"
    PSQL_STDERR_FILE="${tmpdir}/psql.stderr"
    export PSQL_STDERR_FILE
    for role in postgres kbadmin kbdataprotection kbprobe kbmonitoring kbreplicator; do
      printf 'ERROR:  role "%s" already exists\n' "${role}" >> "${PSQL_STDERR_FILE}"
    done
    When run bash "$(script_path)"
    The status should eq 0
    The error should include 'role "postgres" already exists'
    The error should include 'role "kbreplicator" already exists'
    The output should include "restore complete!"
  End

  It "fails when an application role already exists"
    export DATASAFED_LIST_OUT="backup-test.sql.zst"
    export PSQL_STDERR='ERROR:  role "app_owner" already exists'
    When run bash "$(script_path)"
    The status should be failure
    The error should include "non-conflict SQL errors"
    The output should not include "restore complete!"
  End

  It "allows the pre-provisioned postgres database already-exists conflict"
    export DATASAFED_LIST_OUT="backup-test.sql.zst"
    export PSQL_STDERR='ERROR:  database "postgres" already exists'
    When run bash "$(script_path)"
    The status should eq 0
    The error should include 'database "postgres" already exists'
    The output should include "restore complete!"
  End

  It "fails when an incompatible database already exists"
    export DATASAFED_LIST_OUT="backup-test.sql.zst"
    export PSQL_STDERR='ERROR:  database "app" already exists'
    When run bash "$(script_path)"
    The status should be failure
    The error should include "non-conflict SQL errors"
    The output should not include "restore complete!"
  End

  It "does not mask a late SQL error behind a large benign error stream"
    export DATASAFED_LIST_OUT="backup-test.sql.zst"
    PSQL_STDERR_FILE="${tmpdir}/psql.stderr"
    export PSQL_STDERR_FILE
    i=0
    while [ "$i" -lt 4000 ]; do
      printf 'ERROR:  role "postgres" already exists\n' >> "${PSQL_STDERR_FILE}"
      i=$((i + 1))
    done
    printf 'ERROR:  permission denied for schema app\n' >> "${PSQL_STDERR_FILE}"
    When run bash "$(script_path)"
    The status should be failure
    The error should include "non-conflict SQL errors"
    The output should not include "restore complete!"
  End
End
