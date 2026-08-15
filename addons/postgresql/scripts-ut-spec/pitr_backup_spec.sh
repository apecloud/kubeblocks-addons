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
    unset DATASAFED_LIST_EXIT DATASAFED_LIST_OUT DATASAFED_PUSH_EXIT \
      DATASAFED_STAT_EXIT DATASAFED_STAT_OUT MV_EXIT PSQL_EXIT 2>/dev/null || true

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
    printf '%s\n' "${DATASAFED_STAT_OUT:-TotalSize: 0}"
    exit "${DATASAFED_STAT_EXIT:-0}"
    ;;
  list)
    printf '%s' "${DATASAFED_LIST_OUT:-}"
    exit "${DATASAFED_LIST_EXIT:-0}"
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
    cat > "${bindir}/mv" <<'EOF'
#!/bin/sh
printf 'mv %s\n' "$*" >> "${CALL_LOG}"
if [ "${MV_EXIT:-0}" -ne 0 ]; then
  exit "${MV_EXIT}"
fi
exec /bin/mv "$@"
EOF
    chmod +x "${bindir}/datasafed" "${bindir}/psql" "${bindir}/pg_waldump" "${bindir}/mv"
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

  missing_wal_reconciliation_calls_inside_loop() {
    awk '
      /^while true; do$/ { in_loop = 1; next }
      in_loop && /^done$/ { in_loop = 0 }
      in_loop && /uploadMissingLogs/ { calls++ }
      END { print calls + 0 }
    ' ../dataprotection/postgresql-pitr-backup.sh
  }

  retry_same_size_after_publication_failure() {
    export DATASAFED_STAT_OUT="TotalSize: 4096"
    export MV_EXIT=17
    if save_backup_status; then
      return 90
    fi
    export MV_EXIT=0
    save_backup_status
  }

  retry_missing_wal_push_after_failure() {
    export DATASAFED_LIST_OUT='[{"path":"/20260816/000000010000000000000000.zst","mtime":"2026-08-16T00:00:00Z"}]'
    touch "${LOG_DIR}/000000010000000000000001"
    touch "${LOG_DIR}/archive_status/000000010000000000000001.done"
    export DATASAFED_PUSH_EXIT=17
    if uploadMissingLogs; then
      return 90
    fi
    export DATASAFED_PUSH_EXIT=0
    uploadMissingLogs || return
    printf 'push-count=%s\n' "$(grep -c '^datasafed push ' "${CALL_LOG}")"
  }

  reconcile_wal_into_empty_repository() {
    touch "${LOG_DIR}/000000010000000000000001"
    touch "${LOG_DIR}/archive_status/000000010000000000000001.done"
    uploadMissingLogs || return
    local push_count
    push_count=$(grep -c '^datasafed push ' "${CALL_LOG}" || true)
    printf 'push-count=%s\n' "${push_count}"
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

  Describe "uploadMissingLogs()"
    It "fails when the remote WAL listing is unavailable"
      export DATASAFED_LIST_EXIT=17
      When call uploadMissingLogs
      The status should be failure
      The output should include "start to upload the wal log which maybe misses"
      The error should include "datasafed WAL listing failed"
    End

    It "keeps a retry path inside the archive loop after a startup failure"
      When call missing_wal_reconciliation_calls_inside_loop
      The output should eq 1
    End

    It "retries a missing WAL after its first push fails"
      When call retry_missing_wal_push_after_failure
      The status should eq 0
      The output should include "failed to upload 000000010000000000000001, will retry reconciliation"
      The output should include "push-count=2"
    End

    It "fails when a remotely missing done WAL has no local source file"
      export DATASAFED_LIST_OUT='[{"path":"/20260816/000000010000000000000000.zst","mtime":"2026-08-16T00:00:00Z"}]'
      export DATASAFED_STAT_OUT="TotalSize: 4096"
      touch "${LOG_DIR}/archive_status/000000010000000000000001.done"
      When call uploadMissingLogs
      The status should be failure
      The output should include "cannot reconcile 000000010000000000000001: local WAL file is missing"
      The path "${DP_BACKUP_INFO_FILE}" should not be exist
    End

    It "uploads local done WALs when the repository is empty"
      When call reconcile_wal_into_empty_repository
      The status should eq 0
      The output should include "push-count=1"
    End
  End

  Describe "save_backup_status()"
    It "fails clearly when datasafed stat fails instead of retaining stale progress silently"
      export DATASAFED_STAT_EXIT=17
      When call save_backup_status
      The status should be failure
      The error should include "datasafed stat failed"
      The path "${DP_BACKUP_INFO_FILE}" should not be exist
    End

    It "retries the same size after an atomic publication failure"
      When call retry_same_size_after_publication_failure
      The status should eq 0
      The contents of file "${DP_BACKUP_INFO_FILE}" should eq '{"totalSize":"4096"}'
    End

    It "fails without publishing metadata when the WAL repository listing fails"
      export DATASAFED_STAT_OUT="TotalSize: 4096"
      export DATASAFED_LIST_EXIT=17
      When call save_backup_status
      The status should be failure
      The error should include "datasafed WAL listing failed"
      The path "${DP_BACKUP_INFO_FILE}" should not be exist
    End
  End
End
