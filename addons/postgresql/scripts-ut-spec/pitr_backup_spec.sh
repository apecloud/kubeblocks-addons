# shellcheck shell=bash
# Tests the error contract of dataprotection/postgresql-pitr-backup.sh.
# The ActionSet wrapper deliberately does NOT set -e for this script (see
# actionset-postgresql-pitr.yaml): upload failures must be tolerated per file,
# and a failed upload must never mark the WAL segment as .done.
#
# The script runs an infinite archive loop at top level, so the functions are
# extracted with an awk shim instead of Include.

Describe "dataprotection/postgresql-pitr-backup.sh"

  setup() {
    tmpdir=$(mktemp -d -t pg-pitr-backup-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"

    LOG_DIR="${tmpdir}/pg_wal"
    KB_BACKUP_WORKDIR="${tmpdir}/kb-backup"
    DP_BACKUP_INFO_FILE="${tmpdir}/backup.info"
    DP_TARGET_POD_NAME="pod-0"
    TARGET_POD_ROLE="primary"
    mkdir -p "${LOG_DIR}/archive_status"
    export PATH CALL_LOG LOG_DIR KB_BACKUP_WORKDIR DP_BACKUP_INFO_FILE \
      DP_TARGET_POD_NAME TARGET_POD_ROLE
    unset DATASAFED_PUSH_EXIT PSQL_EXIT 2>/dev/null || true

    write_stubs
    build_shim

    # globals normally assigned by the script's top-level code
    PSQL="psql -h localhost -U postgres -d postgres"
    global_backup_in_secondary="f"
    global_old_size=0
    global_stop_time=
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
case "$1" in
  push)
    exit "${DATASAFED_PUSH_EXIT:-0}"
    ;;
  stat)
    echo "TotalSize 0"
    ;;
esac
EOF
    cat > "${bindir}/psql" <<'EOF'
#!/bin/sh
printf 'psql %s\n' "$*" >> "${CALL_LOG}"
if [ "${PSQL_EXIT:-0}" -ne 0 ]; then exit "${PSQL_EXIT}"; fi
echo "f"
EOF
    cat > "${bindir}/pg_waldump" <<'EOF'
#!/bin/sh
exit 0
EOF
    chmod +x "${bindir}/datasafed" "${bindir}/psql" "${bindir}/pg_waldump"
  }

  build_shim() {
    shim="${tmpdir}/shim.sh"
    awk '/^function [a-zA-Z_]/ { capture=1 } capture { print } capture && /^\}/ { capture=0 }' \
      ../dataprotection/postgresql-pitr-backup.sh > "${shim}"
    # shellcheck disable=SC1090
    . ../dataprotection/common-scripts.sh
    # shellcheck disable=SC1090
    . "${shim}"
  }

  call_log() {
    cat "${CALL_LOG}"
  }

  Describe "upload_wal_log()"
    It "does not mark the WAL segment done when the upload fails"
      touch "${LOG_DIR}/000000010000000000000001"
      touch "${LOG_DIR}/archive_status/000000010000000000000001.ready"
      export DATASAFED_PUSH_EXIT=1
      When call upload_wal_log
      The status should eq 0
      The output should include "failed to upload 000000010000000000000001, keeping 000000010000000000000001.ready for retry"
      The path "${LOG_DIR}/archive_status/000000010000000000000001.ready" should be exist
      The path "${LOG_DIR}/archive_status/000000010000000000000001.done" should not be exist
    End

    It "marks the WAL segment done after a successful upload"
      touch "${LOG_DIR}/000000010000000000000001"
      touch "${LOG_DIR}/archive_status/000000010000000000000001.ready"
      When call upload_wal_log
      The status should eq 0
      The output should include "upload 000000010000000000000001"
      The path "${LOG_DIR}/archive_status/000000010000000000000001.done" should be exist
      The path "${LOG_DIR}/archive_status/000000010000000000000001.ready" should not be exist
    End

    It "fails with a clear error when LOG_DIR is not accessible"
      export LOG_DIR="${tmpdir}/does-not-exist"
      When call upload_wal_log
      The status should be failure
      The output should include "failed to cd to ${LOG_DIR}"
      The error should include "No such file or directory"
    End
  End

  Describe "check_pg_process()"
    It "passes when the probe matches the expected role"
      When call check_pg_process
      The status should eq 0
    End

    It "rescues remaining WALs and exits 1 after three failed probes"
      export PSQL_EXIT=1
      When run check_pg_process
      The status should be failure
      The output should include "retry detection!"
      The output should include "Before switching to a new instance, back up any remaining WAL logs."
    End
  End
End
