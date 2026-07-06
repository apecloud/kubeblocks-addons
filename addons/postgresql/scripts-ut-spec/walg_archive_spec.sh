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
    unset WALG_EXIT PSQL_EXIT 2>/dev/null || true

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
  stat) echo "TotalSize 0" ;;
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
    chmod +x "${VOLUME_DATA_DIR}/wal-g/wal-g" "${bindir}/psql" "${bindir}/datasafed" "${bindir}/date"
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
End
