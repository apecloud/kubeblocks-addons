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
    unset DATASAFED_LIST_EXIT DATASAFED_LIST_OUT DATASAFED_PULL_EXIT DATASAFED_PUSH_EXIT \
      DATASAFED_RM_EXIT DATASAFED_RM_FAIL_PATH \
      DATASAFED_STAT_EXIT DATASAFED_STAT_OUT DATE_D_EXIT DATE_D_OUT DATE_TODAY_OUT \
      DP_TTL_SECONDS PG_WALDUMP_EXIT PG_WALDUMP_OUT \
      MV_EXIT PSQL_EXIT 2>/dev/null || true

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
  pull)
    exit "${DATASAFED_PULL_EXIT:-0}"
    ;;
  stat)
    printf '%s\n' "${DATASAFED_STAT_OUT:-TotalSize: 0}"
    exit "${DATASAFED_STAT_EXIT:-0}"
    ;;
  list)
    printf '%s' "${DATASAFED_LIST_OUT:-}"
    exit "${DATASAFED_LIST_EXIT:-0}"
    ;;
  rm)
    if [ -n "${DATASAFED_RM_FAIL_PATH:-}" ] && [ "$2" = "${DATASAFED_RM_FAIL_PATH}" ]; then
      exit 17
    fi
    exit "${DATASAFED_RM_EXIT:-0}"
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
printf '%s' "${PG_WALDUMP_OUT:-}"
exit "${PG_WALDUMP_EXIT:-0}"
EOF
    cat > "${bindir}/date" <<'EOF'
#!/bin/sh
if [ "$1" = "-d" ] && [ -n "${DATE_D_OUT:-}" ]; then
  if [ "${DATE_D_EXIT:-0}" -ne 0 ]; then
    exit "${DATE_D_EXIT}"
  fi
  printf '%s\n' "${DATE_D_OUT}"
elif [ "$1" = "+%Y%m%d" ] && [ -n "${DATE_TODAY_OUT:-}" ]; then
  printf '%s\n' "${DATE_TODAY_OUT}"
else
  exec /bin/date "$@"
fi
EOF
    cat > "${bindir}/mv" <<'EOF'
#!/bin/sh
printf 'mv %s\n' "$*" >> "${CALL_LOG}"
if [ "${MV_EXIT:-0}" -ne 0 ]; then
  exit "${MV_EXIT}"
fi
exec /bin/mv "$@"
EOF
    chmod +x "${bindir}/datasafed" "${bindir}/psql" "${bindir}/pg_waldump" \
      "${bindir}/date" "${bindir}/mv"
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

  refresh_missing_cached_oldest_wal() {
    local oldest_wal="/20260816/000000010000000000000001.zst"
    mkdir -p "${KB_BACKUP_WORKDIR}"
    printf '%s\n' "${oldest_wal}" > "${KB_BACKUP_WORKDIR}/dp_oldest_file.info"
    export DATASAFED_STAT_OUT="TotalSize: 4096"
    export DATASAFED_LIST_OUT="[{\"path\":\"${oldest_wal}\",\"mtime\":\"2026-08-16T00:00:00Z\"}]"
    save_backup_status || return
    local pull_count
    pull_count=$(grep -c '^datasafed pull ' "${CALL_LOG}" || true)
    printf 'pull-count=%s\n' "${pull_count}"
  }

  purge_and_report_checkpoint() {
    global_last_purge_time=123
    local status=0
    purge_expired_files || status=$?
    printf 'purge-checkpoint=%s\n' "${global_last_purge_time}"
    return "${status}"
  }

  Describe "purge_expired_files()"
    It "fails without advancing the checkpoint when the expired-WAL listing fails"
      export DP_TTL_SECONDS=3600 DATASAFED_LIST_EXIT=17
      When call purge_and_report_checkpoint
      The status should be failure
      The error should include "failed to list expired WAL files"
      The output should include "purge-checkpoint=123"
      The path "${DP_BACKUP_INFO_FILE}" should not be exist
    End

    It "reports only successful deletions and keeps the checkpoint when one deletion fails"
      removed_wal="/20260816/000000010000000000000001.zst"
      failed_wal="/20260816/000000010000000000000002.zst"
      export DP_TTL_SECONDS=3600 DATASAFED_LIST_OUT="${removed_wal} ${failed_wal}"
      export DATASAFED_RM_FAIL_PATH="${failed_wal}"
      When call purge_and_report_checkpoint
      The status should be failure
      The error should include "failed to remove expired WAL: ${failed_wal}"
      The output should include "cleanup expired wal-log files: ${removed_wal}"
      The output should not include "cleanup expired wal-log files: ${failed_wal}"
      The output should include "purge-checkpoint=123"
      The path "${DP_BACKUP_INFO_FILE}" should not be exist
    End

    It "publishes the reduced size after a successful expiration pass"
      expired_wal="/20260816/000000010000000000000001.zst"
      global_last_purge_time=123
      export DP_TTL_SECONDS=3600 DATASAFED_LIST_OUT="${expired_wal}"
      export DATASAFED_STAT_OUT="TotalSize: 2048"
      When call purge_expired_files
      The status should eq 0
      The output should include "cleanup expired wal-log files: ${expired_wal}"
      The contents of file "${DP_BACKUP_INFO_FILE}" should eq '{"totalSize":"2048"}'
    End

    It "keeps the checkpoint when reduced-size lookup fails"
      expired_wal="/20260816/000000010000000000000001.zst"
      export DP_TTL_SECONDS=3600 DATASAFED_LIST_OUT="${expired_wal}"
      export DATASAFED_STAT_EXIT=17
      When call purge_and_report_checkpoint
      The status should be failure
      The error should include "datasafed stat failed"
      The output should include "purge-checkpoint=123"
      The path "${DP_BACKUP_INFO_FILE}" should not be exist
    End

    It "keeps the checkpoint when reduced-size publication fails"
      expired_wal="/20260816/000000010000000000000001.zst"
      export DP_TTL_SECONDS=3600 DATASAFED_LIST_OUT="${expired_wal}"
      export DATASAFED_STAT_OUT="TotalSize: 2048" MV_EXIT=17
      When call purge_and_report_checkpoint
      The status should be failure
      The output should include "purge-checkpoint=123"
      The path "${DP_BACKUP_INFO_FILE}" should not be exist
    End
  End

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

    It "does not let a timeline-history object hide a missing WAL"
      wal_name="000000010000000000000001"
      export DATASAFED_LIST_OUT='[
        {"path":"/00000002.history.zst","mtime":"2026-08-15T23:59:00Z"},
        {"path":"/20260816/000000010000000000000000.zst","mtime":"2026-08-16T00:00:00Z"}
      ]'
      export DATE_TODAY_OUT="20260816"
      touch "${LOG_DIR}/${wal_name}"
      touch "${LOG_DIR}/archive_status/${wal_name}.done"
      When call uploadMissingLogs
      The status should eq 0
      The result of function call_log should include "datasafed push -z zstd ${wal_name} /20260816/${wal_name}.zst"
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

    It "fails without caching or publishing when the oldest WAL pull fails"
      export DATASAFED_STAT_OUT="TotalSize: 4096"
      export DATASAFED_LIST_OUT='[{"path":"/20260816/000000010000000000000001.zst","mtime":"2026-08-16T00:00:00Z"}]'
      export DATASAFED_PULL_EXIT=17
      When call save_backup_status
      The status should be failure
      The error should include "failed to pull oldest WAL"
      The path "${KB_BACKUP_WORKDIR}/dp_oldest_file.info" should not be exist
      The path "${DP_BACKUP_INFO_FILE}" should not be exist
    End

    It "ignores an older timeline-history object when deriving the WAL start"
      history_path="/00000002.history.zst"
      wal_path="/20260816/000000010000000000000001.zst"
      export DATASAFED_STAT_OUT="TotalSize: 4096"
      export DATASAFED_LIST_OUT="[{
        \"path\":\"${history_path}\",\"mtime\":\"2026-08-15T23:59:00Z\"
      },{
        \"path\":\"${wal_path}\",\"mtime\":\"2026-08-16T00:00:00Z\"
      }]"
      export PG_WALDUMP_OUT='rmgr: Transaction desc: COMMIT 2026-08-16T00:00:00Z; origin: node'
      export DATE_D_OUT="2026-08-16T00:00:00Z"
      When call save_backup_status
      The status should eq 0
      The result of function call_log should not include "${history_path}"
      The contents of file "${DP_BACKUP_INFO_FILE}" should eq '{"totalSize":"4096"}'
    End


    It "fails without publishing when oldest WAL analysis fails"
      export DATASAFED_STAT_OUT="TotalSize: 4096"
      export DATASAFED_LIST_OUT='[{"path":"/20260816/000000010000000000000001.zst","mtime":"2026-08-16T00:00:00Z"}]'
      export PG_WALDUMP_EXIT=17
      When call save_backup_status
      The status should be failure
      The error should include "failed to analyze oldest WAL"
      The path "${DP_BACKUP_INFO_FILE}" should not be exist
    End

    It "fails without publishing when oldest WAL timestamp normalization fails"
      export DATASAFED_STAT_OUT="TotalSize: 4096"
      export DATASAFED_LIST_OUT='[{"path":"/20260816/000000010000000000000001.zst","mtime":"2026-08-16T00:00:00Z"}]'
      export PG_WALDUMP_OUT='rmgr: Transaction desc: COMMIT 2026-08-16T00:00:00Z; origin: node'
      export DATE_D_OUT="2026-08-16T00:00:00Z" DATE_D_EXIT=17
      When call save_backup_status
      The status should be failure
      The error should include "failed to normalize oldest WAL timestamp"
      The path "${DP_BACKUP_INFO_FILE}" should not be exist
    End

    It "uses a commit record from a partial oldest WAL despite pg_waldump's final nonzero status"
      export DATASAFED_LIST_OUT='[{"path":"/20260816/000000010000000000000001.zst","mtime":"2026-08-16T00:00:00Z"}]'
      export PG_WALDUMP_OUT='rmgr: Transaction desc: COMMIT 2026-08-16T00:00:00Z; origin: node'
      export PG_WALDUMP_EXIT=17
      export DATE_D_OUT="2026-08-16T00:00:00Z"
      When call get_start_time_for_range
      The status should eq 0
      The output should eq "2026-08-16T00:00:00Z"
    End

    It "refreshes a matching oldest-WAL cache when its local artifact is missing"
      When call refresh_missing_cached_oldest_wal
      The status should eq 0
      The output should include "pull-count=1"
    End
  End
End
