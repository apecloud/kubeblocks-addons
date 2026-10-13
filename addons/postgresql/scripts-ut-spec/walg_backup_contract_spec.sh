# shellcheck shell=bash

Describe "WAL-G backup connection contract"
  setup() {
    tmpdir=$(mktemp -d -t pg-walg-backup-XXXXXX)
    bindir="${tmpdir}/bin"
    dataprotection_dir=$(cd ../dataprotection && pwd)
    mkdir -p "${bindir}" "${tmpdir}/volume" "${tmpdir}/data"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"
    DP_DATASAFED_BIN_PATH="${bindir}"
    DP_BACKUP_BASE_PATH="/repository/current"
    DP_BACKUP_NAME="backup-test"
    DP_PARENT_BACKUP_NAME="parent"
    DP_BACKUP_INFO_FILE="${tmpdir}/backup-info"
    DP_DB_PASSWORD="secret"
    DP_DB_USER="postgres"
    DP_DB_HOST="postgres.example.test"
    DP_DB_PORT="6432"
    VOLUME_DATA_DIR="${tmpdir}/volume"
    DATA_DIR="${tmpdir}/data"
    export PATH CALL_LOG DP_DATASAFED_BIN_PATH DP_BACKUP_BASE_PATH \
      DP_BACKUP_NAME DP_PARENT_BACKUP_NAME DP_BACKUP_INFO_FILE \
      DP_DB_PASSWORD DP_DB_USER DP_DB_HOST DP_DB_PORT VOLUME_DATA_DIR DATA_DIR
    unset FAIL_SWITCH_WAL 2>/dev/null || true
    write_stubs
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  write_stubs() {
    cat > "${bindir}/cp" <<'EOF'
#!/bin/sh
printf 'cp %s\n' "$*" >> "${CALL_LOG}"
exit 0
EOF
    cat > "${bindir}/psql" <<'EOF'
#!/bin/sh
printf 'psql %s\n' "$*" >> "${CALL_LOG}"
case "$*" in
  *archive_command*) printf '%s\n' 'wal-g wal-push %p' ;;
  *pg_switch_wal*)
    if [ "${FAIL_SWITCH_WAL:-0}" -eq 1 ]; then
      exit 2
    fi
    ;;
esac
EOF
    cat > "${bindir}/wal-g" <<'EOF'
#!/bin/sh
printf 'wal-g PGHOST=%s PGUSER=%s PGPORT=%s args=%s\n' \
  "${PGHOST}" "${PGUSER}" "${PGPORT}" "$*" >> "${CALL_LOG}"
printf '%s\n' 'Wrote backup with name base_000000010000000000000001'
EOF
    cat > "${bindir}/datasafed" <<'EOF'
#!/bin/sh
printf 'datasafed %s\n' "$*" >> "${CALL_LOG}"
case "$1" in
  list) printf '%s\n' "$2" ;;
  push) cat > /dev/null ;;
  pull)
    case "$2" in
      wal-g-backup-name) printf '%s\n' 'base_parent' > "$3" ;;
      *) printf '%s\n' '{"FinishTime":"2026-01-01T00:01:00Z","StartTime":"2026-01-01T00:00:00Z","CompressedSize":42}' > "$3" ;;
    esac
    ;;
esac
EOF
    cat > "${bindir}/jq" <<'EOF'
#!/bin/sh
case "$*" in
  *FinishTime*) printf '%s\n' '2026-01-01T00:01:00Z' ;;
  *StartTime*) printf '%s\n' '2026-01-01T00:00:00Z' ;;
  *CompressedSize*) printf '%s\n' '42' ;;
esac
EOF
    chmod +x "${bindir}/cp" "${bindir}/psql" "${bindir}/wal-g" \
      "${bindir}/datasafed" "${bindir}/jq"
  }

  call_log() {
    cat "${CALL_LOG}"
  }

  run_backup() {
    (cd "${tmpdir}" && bash "${dataprotection_dir}/$1")
  }

  It "executes full backup and WAL switch against the ActionSet endpoint"
    When call run_backup "wal-g-backup.sh"
    The status should eq 0
    The result of function call_log should include "psql -h postgres.example.test -U postgres -p 6432 -d postgres"
    The result of function call_log should include "wal-g PGHOST=postgres.example.test PGUSER=postgres PGPORT=6432"
    The result of function call_log should not include "CLUSTER_COMPONENT_NAME"
  End

  It "executes incremental backup and WAL switch against the ActionSet endpoint"
    When call run_backup "wal-g-incremental-backup.sh"
    The status should eq 0
    The result of function call_log should include "psql -h postgres.example.test -U postgres -p 6432 -d postgres"
    The result of function call_log should include "wal-g PGHOST=postgres.example.test PGUSER=postgres PGPORT=6432"
    The result of function call_log should not include "CLUSTER_COMPONENT_NAME"
  End

  It "fails a full backup when the WAL switch control command fails"
    export FAIL_SWITCH_WAL=1
    When call run_backup "wal-g-backup.sh"
    The status should be failure
    The output should include "failed with exit code 2"
    The path "${DP_BACKUP_INFO_FILE}.exit" should be file
  End

  It "fails an incremental backup when the WAL switch control command fails"
    export FAIL_SWITCH_WAL=1
    When call run_backup "wal-g-incremental-backup.sh"
    The status should be failure
    The output should include "failed with exit code 2"
    The path "${DP_BACKUP_INFO_FILE}.exit" should be file
  End
End
