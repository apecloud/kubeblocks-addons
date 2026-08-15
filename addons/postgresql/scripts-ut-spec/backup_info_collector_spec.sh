# shellcheck shell=bash

Describe "dataprotection/backup-info-collector.sh"
  setup() {
    tmpdir=$(mktemp -d -t pg-backup-info-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"
    DP_DB_USER="kbdataprotection"
    DP_DB_HOST="postgres.example.test"
    DP_DB_PORT="6432"
    DP_DATASAFED_BIN_PATH="${bindir}"
    DP_BACKUP_BASE_PATH="/repository/backup-test"
    DP_BACKUP_INFO_FILE="${tmpdir}/backup-info"
    export PATH CALL_LOG DP_DB_USER DP_DB_HOST DP_DB_PORT \
      DP_DATASAFED_BIN_PATH DP_BACKUP_BASE_PATH DP_BACKUP_INFO_FILE
    unset DATASAFED_STAT_OUT 2>/dev/null || true
    write_stubs
    . ../dataprotection/backup-info-collector.sh
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  write_stubs() {
    cat > "${bindir}/psql" <<'EOF'
#!/bin/sh
printf 'psql %s\n' "$*" >> "${CALL_LOG}"
printf '%s\n' '2026-08-15 15:00:00'
EOF
    cat > "${bindir}/date" <<'EOF'
#!/bin/sh
case "$*" in
  *15:00:00*) printf '%s\n' '2026-08-15T15:00:00Z' ;;
  *15:01:00*) printf '%s\n' '2026-08-15T15:01:00Z' ;;
  *) exit 2 ;;
esac
EOF
    cat > "${bindir}/datasafed" <<'EOF'
#!/bin/sh
printf 'datasafed %s\n' "$*" >> "${CALL_LOG}"
if [ "$1" = "stat" ]; then
  printf '%s\n' "${DATASAFED_STAT_OUT:-TotalSize: 4096}"
fi
EOF
    chmod +x "${bindir}/psql" "${bindir}/date" "${bindir}/datasafed"
  }

  call_log() {
    cat "${CALL_LOG}"
  }

  It "queries time through the ActionSet-injected database port"
    When call get_current_time
    The status should eq 0
    The output should eq "2026-08-15 15:00:00"
    The result of function call_log should include "psql -U kbdataprotection -h postgres.example.test -p 6432 -d postgres"
  End

  It "writes the byte count from the real datasafed TotalSize format"
    # apecloud/datasafed cmd/stat.go emits: TotalSize: <integer>
    export DATASAFED_STAT_OUT="TotalSize: 4096"
    When call stat_and_save_backup_info "2026-08-15 15:00:00" "2026-08-15 15:01:00"
    The status should eq 0
    The contents of file "${DP_BACKUP_INFO_FILE}" should include '"totalSize":"4096"'
    The result of function call_log should include "datasafed stat /"
  End

  It "rejects a successful datasafed response without a numeric byte count"
    export DATASAFED_STAT_OUT="TotalSize:"
    When call stat_and_save_backup_info "2026-08-15 15:00:00" "2026-08-15 15:01:00"
    The status should be failure
    The error should include "datasafed stat returned an invalid TotalSize"
    The path "${DP_BACKUP_INFO_FILE}" should not be exist
  End
End
