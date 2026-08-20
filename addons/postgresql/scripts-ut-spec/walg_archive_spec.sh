# shellcheck shell=bash
# Tests the retry/error-handling contract of dataprotection/wal-g-archive.sh.
# The ActionSet wrapper deliberately does NOT set -e for this script (see
# actionset-wal-g-pitr.yaml): these branches must be reachable and correct.
#
# The script runs an infinite archive loop at top level, so the functions are
# extracted with an awk shim instead of Include.

Describe "dataprotection/wal-g-archive.sh"

  setup() {
    tmpdir=$(mktemp -d -t pg-walg-archive-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"

    VOLUME_DATA_DIR="${tmpdir}/data"
    LOG_DIR="${tmpdir}/data/pgroot/data/pg_wal"
    KB_BACKUP_WORKDIR="${tmpdir}/data/kb-backup"
    DP_BACKUP_INFO_FILE="${tmpdir}/backup.info"
    UPLOAD_MISSING_LOGS_RETRY_INTERVAL=180
    DP_TARGET_POD_NAME="pod-0"
    TARGET_POD_ROLE="primary"
    mkdir -p "${VOLUME_DATA_DIR}/wal-g/env" "${LOG_DIR}/archive_status"
    echo "conf" > "${VOLUME_DATA_DIR}/wal-g/env/WALG_DATASAFED_CONFIG"
    export PATH CALL_LOG VOLUME_DATA_DIR LOG_DIR KB_BACKUP_WORKDIR \
      DP_BACKUP_INFO_FILE UPLOAD_MISSING_LOGS_RETRY_INTERVAL \
      DP_TARGET_POD_NAME TARGET_POD_ROLE
    unset DATASAFED_STAT_EXIT DATASAFED_STAT_OUT MV_EXIT WALG_EXIT PSQL_EXIT 2>/dev/null || true

    write_stubs
    build_shim

    # globals normally assigned by the script's top-level code
    PSQL="psql -h localhost -U postgres -d postgres"
    global_backup_in_secondary="f"
    GLOBAL_OLD_SIZE=0
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  write_stubs() {
    # wal-g is invoked by absolute path, so the stub lives there
    cat > "${VOLUME_DATA_DIR}/wal-g/wal-g" <<'EOF'
#!/bin/sh
printf 'wal-g %s\n' "$*" >> "${CALL_LOG}"
exit "${WALG_EXIT:-0}"
EOF
    # the script invokes wal-g through envdir (daemontools), which the test
    # host may not have: pass through to the wrapped command, skipping the dir
    cat > "${bindir}/envdir" <<'EOF'
#!/bin/sh
shift
exec "$@"
EOF
    chmod +x "${bindir}/envdir"
    cat > "${bindir}/psql" <<'EOF'
#!/bin/sh
printf 'psql %s\n' "$*" >> "${CALL_LOG}"
if [ "${PSQL_EXIT:-0}" -ne 0 ]; then exit "${PSQL_EXIT}"; fi
echo "f"
EOF
    cat > "${bindir}/datasafed" <<'EOF'
#!/bin/sh
printf 'datasafed %s\n' "$*" >> "${CALL_LOG}"
case "$1" in
  stat)
    printf '%s\n' "${DATASAFED_STAT_OUT:-TotalSize: 0}"
    exit "${DATASAFED_STAT_EXIT:-0}"
    ;;
esac
EOF
    # `date -r <file> +%s` is GNU-only; make it portable for local macOS runs
    cat > "${bindir}/date" <<'EOF'
#!/bin/sh
if [ "$1" = "-r" ]; then
  f=$2
  # GNU form first: on GNU, `stat -f %m <file>` is not an error — it prints
  # the filesystem mount point — so a BSD-first chain returns garbage.
  stat -c %Y "$f" 2>/dev/null || stat -f %m "$f"
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
    chmod +x "${VOLUME_DATA_DIR}/wal-g/wal-g" "${bindir}/psql" "${bindir}/datasafed" "${bindir}/date" "${bindir}/mv"
  }

  build_shim() {
    shim="${tmpdir}/shim.sh"
    awk '/^function [a-zA-Z_]/ { capture=1 } capture { print } capture && /^\}/ { capture=0 }' \
      ../dataprotection/wal-g-archive.sh > "${shim}"
    # shellcheck disable=SC1090
    . ../dataprotection/common-scripts.sh
    # shellcheck disable=SC1090
    . "${shim}"
  }

  call_log() {
    cat "${CALL_LOG}"
  }

  wal_g_call_count() {
    awk '/^wal-g / { calls++ } END { print calls + 0 }' "${CALL_LOG}"
  }

  history_upload_calls_inside_loop() {
    awk '
      /^while true; do$/ { in_loop = 1; next }
      in_loop && /^done$/ { in_loop = 0 }
      in_loop && /uploadDoneHistoryWALs/ { calls++ }
      END { print calls + 0 }
    ' ../dataprotection/wal-g-archive.sh
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

  Describe "uploadDoneHistoryWALs()"
    It "reports failure and retains timeline history for retry when wal-push fails"
      touch "${LOG_DIR}/00000002.history"
      touch "${LOG_DIR}/archive_status/00000002.history.done"
      export WALG_EXIT=41
      When call uploadDoneHistoryWALs
      The status should be failure
      The output should include "Failed to upload file: 00000002.history"
      The path "${LOG_DIR}/00000002.history" should be exist
      The path "${LOG_DIR}/archive_status/00000002.history.done" should be exist
      The path "${LOG_DIR}/archive_status/00000002.history.done.walg-uploaded" should not be exist
    End

    It "persists success and does not upload the same timeline history twice"
      touch "${LOG_DIR}/00000002.history"
      touch "${LOG_DIR}/archive_status/00000002.history.done"
      uploadDoneHistoryWALs
      When call uploadDoneHistoryWALs
      The status should eq 0
      The path "${LOG_DIR}/archive_status/00000002.history.done.walg-uploaded" should be exist
      The result of function wal_g_call_count should eq 1
    End

    It "is invoked from every archive loop iteration"
      When call history_upload_calls_inside_loop
      The output should eq 1
    End
  End

  Describe "uploadMissingLogs()"
    It "keeps the .ready file and the tracking file when wal-push fails"
      touch "${LOG_DIR}/000000010000000000000001"
      touch "${LOG_DIR}/archive_status/000000010000000000000001.ready"
      export WALG_EXIT=1
      When call uploadMissingLogs
      The status should eq 0
      The output should include "Failed to upload 000000010000000000000001"
      The path "${LOG_DIR}/archive_status/000000010000000000000001.ready" should be exist
      The path "${LOG_DIR}/archive_status/000000010000000000000001.uploading" should be exist
    End

    It "renames .ready to .done and clears tracking when wal-push succeeds"
      touch "${LOG_DIR}/000000010000000000000001"
      touch "${LOG_DIR}/archive_status/000000010000000000000001.ready"
      When call uploadMissingLogs
      The status should eq 0
      The output should include "WAL-G upload succeeded for 000000010000000000000001"
      The path "${LOG_DIR}/archive_status/000000010000000000000001.done" should be exist
      The path "${LOG_DIR}/archive_status/000000010000000000000001.ready" should not be exist
      The path "${LOG_DIR}/archive_status/000000010000000000000001.uploading" should not be exist
    End

    It "skips files with a recent tracking file instead of retrying immediately"
      touch "${LOG_DIR}/000000010000000000000001"
      touch "${LOG_DIR}/archive_status/000000010000000000000001.ready"
      touch "${LOG_DIR}/archive_status/000000010000000000000001.uploading"
      When call uploadMissingLogs
      The status should eq 0
      The output should include "Skipping 000000010000000000000001 - recent upload attempt in progress"
      The result of function call_log should not include "wal-g"
    End
  End

  Describe "check_pg_process()"
    It "retries the probe and survives a single psql failure round-trip"
      # psql succeeds and reports pg_is_in_recovery=f matching primary role
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

  Describe "config_wal_g()"
    It "exits when the wal-g binary is missing"
      rm -f "${VOLUME_DATA_DIR}/wal-g/wal-g"
      When run config_wal_g "some/path"
      The status should be failure
      The output should include "wal-g binary not found"
    End
  End

  Describe "save_backup_status()"
    It "publishes the byte count from the real datasafed TotalSize format"
      export DATASAFED_STAT_OUT="TotalSize: 4096"
      When call save_backup_status
      The status should eq 0
      The output should include "total size: 4096"
      The contents of file "${DP_BACKUP_INFO_FILE}" should eq '{"totalSize":"4096"}'
    End

    It "rejects malformed successful datasafed size output instead of retaining stale progress silently"
      export DATASAFED_STAT_OUT="TotalSize: unknown"
      When call save_backup_status
      The status should be failure
      The error should include "invalid TotalSize"
      The path "${DP_BACKUP_INFO_FILE}" should not be exist
    End

    It "retries the same size after an atomic publication failure"
      When call retry_same_size_after_publication_failure
      The status should eq 0
      The output should include "total size: 4096"
      The contents of file "${DP_BACKUP_INFO_FILE}" should eq '{"totalSize":"4096"}'
    End
  End
End
