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
    unset DATASAFED_LIST_OUT DATASAFED_PULL_EXIT PSQL_EXIT PSQL_STDERR \
      PSQL_STDERR_REPEAT 2>/dev/null || true
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
if [ -n "${PSQL_STDERR_REPEAT:-}" ]; then
  awk -v line="${PSQL_STDERR:-}" -v count="${PSQL_STDERR_REPEAT}" \
    'BEGIN { for (i = 0; i < count; i++) print line }' >&2
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
    The output should not include "restore complete!"
    The error should include "pgdumpall restore pipeline failed"
  End

  It "fails when datasafed pull fails mid-stream"
    export DATASAFED_LIST_OUT="backup-test.sql.zst"
    export DATASAFED_PULL_EXIT=1
    When run bash "$(script_path)"
    The status should be failure
    The output should not include "restore complete!"
    The error should include "pgdumpall restore pipeline failed"
  End

  It "allows pre-provisioned objects that already exist"
    export DATASAFED_LIST_OUT="backup-test.sql.zst"
    export PSQL_STDERR='ERROR: role "postgres" already exists'
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "restore complete!"
    The error should include "already exists"
  End

  It "fails when psql reports a non-conflict SQL error"
    export DATASAFED_LIST_OUT="backup-test.sql.zst"
    export PSQL_STDERR='ERROR: permission denied for schema public'
    When run bash "$(script_path)"
    The status should be failure
    The output should not include "restore complete!"
    The error should include "non-conflict SQL errors"
  End

  It "fails when a large psql error stream closes grep -q early"
    export DATASAFED_LIST_OUT="backup-test.sql.zst"
    export PSQL_STDERR='ERROR: x'
    export PSQL_STDERR_REPEAT=4096
    When run bash "$(script_path)"
    The status should be failure
    The output should not include "restore complete!"
    The error should include "non-conflict SQL errors"
  End
End
