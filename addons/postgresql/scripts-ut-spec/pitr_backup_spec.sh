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
      DATASAFED_PUSH_FAIL_WAL \
      DATASAFED_RM_EXIT DATASAFED_RM_FAIL_PATH \
      DATASAFED_STAT_EXIT DATASAFED_STAT_OUT DATE_D_EXIT DATE_D_OUT DATE_EPOCH_EXIT DATE_EPOCH_FAIL_ON_CALL DATE_EPOCH_OUT DATE_TODAY_EXIT DATE_TODAY_OUT \
      DP_TTL_SECONDS FIND_EXIT FIND_FAIL_ON_CALL LS_EXIT PG_WALDUMP_EXIT PG_WALDUMP_OUT \
      MV_EXIT MV_FAIL_SOURCE PSQL_EXIT PSQL_FAIL_ON_CALL 2>/dev/null || true

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
    if [ -n "${DATASAFED_PUSH_FAIL_WAL:-}" ] && [ "$4" = "${DATASAFED_PUSH_FAIL_WAL}" ]; then
      exit 17
    fi
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
call_count=$(awk '/^psql / { calls++ } END { print calls + 0 }' "${CALL_LOG}")
if [ "${PSQL_FAIL_ON_CALL:-0}" -ne 0 ]; then
  if [ "${PSQL_FAIL_ON_CALL}" -eq "${call_count}" ]; then exit "${PSQL_EXIT:-17}"; fi
elif [ "${PSQL_EXIT:-0}" -ne 0 ]; then
  exit "${PSQL_EXIT}"
fi
echo "f"
EOF
    cat > "${bindir}/pg_waldump" <<'EOF'
#!/bin/sh
printf '%s' "${PG_WALDUMP_OUT:-}"
exit "${PG_WALDUMP_EXIT:-0}"
EOF
    cat > "${bindir}/date" <<'EOF'
#!/bin/sh
if [ "$1" = "+%s" ]; then
  printf 'date %s\n' "$*" >> "${CALL_LOG}"
  call_count=$(awk '/^date \+%s$/ { calls++ } END { print calls + 0 }' "${CALL_LOG}")
  if [ "${DATE_EPOCH_FAIL_ON_CALL:-0}" -eq "${call_count}" ]; then
    exit 17
  elif [ "${DATE_EPOCH_EXIT:-0}" -ne 0 ]; then
    exit "${DATE_EPOCH_EXIT}"
  elif [ -n "${DATE_EPOCH_OUT:-}" ]; then
    printf '%s\n' "${DATE_EPOCH_OUT}"
  else
    exec /bin/date "$@"
  fi
elif [ "$1" = "-d" ] && [ -n "${DATE_D_OUT:-}" ]; then
  if [ "${DATE_D_EXIT:-0}" -ne 0 ]; then
    exit "${DATE_D_EXIT}"
  fi
  printf '%s\n' "${DATE_D_OUT}"
elif [ "$1" = "+%Y%m%d" ]; then
  if [ "${DATE_TODAY_EXIT:-0}" -ne 0 ]; then
    exit "${DATE_TODAY_EXIT}"
  elif [ -n "${DATE_TODAY_OUT:-}" ]; then
    printf '%s\n' "${DATE_TODAY_OUT}"
  else
    exec /bin/date "$@"
  fi
else
  exec /bin/date "$@"
fi
EOF
    cat > "${bindir}/sleep" <<'EOF'
#!/bin/sh
exit 0
EOF
    cat > "${bindir}/find" <<'EOF'
#!/bin/sh
printf 'find %s\n' "$*" >> "${CALL_LOG}"
call_count=$(awk '/^find / { calls++ } END { print calls + 0 }' "${CALL_LOG}")
if [ "${FIND_FAIL_ON_CALL:-0}" -eq "${call_count}" ]; then
  exit 17
elif [ "${FIND_EXIT:-0}" -ne 0 ]; then
  exit "${FIND_EXIT}"
fi
exec /usr/bin/find "$@"
EOF
    cat > "${bindir}/ls" <<'EOF'
#!/bin/sh
printf 'ls %s\n' "$*" >> "${CALL_LOG}"
if [ "${LS_EXIT:-0}" -ne 0 ]; then
  exit "${LS_EXIT}"
fi
exec /bin/ls "$@"
EOF
    cat > "${bindir}/mv" <<'EOF'
#!/bin/sh
printf 'mv %s\n' "$*" >> "${CALL_LOG}"
if [ -n "${MV_FAIL_SOURCE:-}" ] && [ "$2" = "${MV_FAIL_SOURCE}" ]; then
  exit 17
fi
if [ "${MV_EXIT:-0}" -ne 0 ]; then
  exit "${MV_EXIT}"
fi
exec /bin/mv "$@"
EOF
    chmod +x "${bindir}/datasafed" "${bindir}/psql" "${bindir}/pg_waldump" \
      "${bindir}/date" "${bindir}/find" "${bindir}/ls" "${bindir}/mv" "${bindir}/sleep"
  }

  build_shim() {
    shim="${tmpdir}/shim.sh"
    awk '/^function [a-zA-Z_]/ { capture=1 } capture { print } capture && /^\}/ { capture=0 }' \
      ../dataprotection/postgresql-pitr-backup.sh > "${shim}"
    awk '
      /^while true; do$/ {
        print "archive_loop_once() {"
        capture = 1
        next
      }
      capture && /^done$/ {
        print "}"
        exit
      }
      capture {
        if ($0 ~ /^[[:space:]]*continue[[:space:]]*$/) {
          print "    return 1"
        } else {
          print
        }
      }
    ' ../dataprotection/postgresql-pitr-backup.sh >> "${shim}"
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

  switch_and_report_checkpoint() {
    global_last_switch_wal_time=123
    global_switch_wal_interval=0
    local status=0
    switch_wal_log || status=$?
    printf 'switch-checkpoint=%s\n' "${global_last_switch_wal_time}"
    return "${status}"
  }

  upload_and_report_stop_time() {
    global_stop_time="2026-08-15T23:59:00Z"
    local status=0
    upload_wal_log || status=$?
    printf 'stop-time=%s\n' "${global_stop_time}"
    return "${status}"
  }

  run_startup_preamble() {
    startup="${tmpdir}/startup.sh"
    awk '/^# clean up expired logfiles/ { exit } { print }' \
      ../dataprotection/postgresql-pitr-backup.sh > "${startup}"
    # shellcheck disable=SC1090
    . "${startup}"
    printf 'switch-time=%s retention-time=%s\n' \
      "${global_last_switch_wal_time}" "${global_last_purge_time}"
  }

  Describe "startup clock initialization"
    It "fails when the initial WAL switch clock is not a decimal epoch"
      export DATE_EPOCH_OUT="not-an-epoch"
      When run run_startup_preamble
      The status should be failure
      The output should include "failed to determine initial WAL switch time"
      The output should not include "switch-time=not-an-epoch"
    End

    It "fails when the initial WAL switch clock cannot be read"
      export DATE_EPOCH_FAIL_ON_CALL=1
      When run run_startup_preamble
      The status should be failure
      The output should include "failed to determine initial WAL switch time"
      The output should not include "failed to determine initial WAL retention time"
    End

    It "fails when the initial WAL retention clock cannot be read"
      export DATE_EPOCH_FAIL_ON_CALL=2
      When run run_startup_preamble
      The status should be failure
      The output should include "failed to determine initial WAL retention time"
      The output should not include "failed to determine initial WAL switch time"
    End
  End

  archive_round_with_upload_listing_failure() {
    global_missing_logs_reconciled=true
    check_pg_process() { :; }
    switch_wal_log() { :; }
    purge_expired_files() { printf 'purge_expired_files\n' >> "${CALL_LOG}"; }
    export LS_EXIT=17
    archive_loop_once
  }

  Describe "archive loop"
    It "stops the round before metadata and retention after a hard upload failure"
      When call archive_round_with_upload_listing_failure
      The status should be failure
      The output should include "failed to list WAL archive status"
      The contents of file "${CALL_LOG}" should not include "datasafed stat"
      The contents of file "${CALL_LOG}" should not include "purge_expired_files"
    End
  End

  Describe "switch_wal_log()"
    It "fails before arithmetic when the current time is not a decimal epoch"
      export DATE_EPOCH_OUT="not-an-epoch"
      When call switch_and_report_checkpoint
      The status should be failure
      The output should include "failed to determine current time for WAL switch"
      The output should include "switch-checkpoint=123"
      The contents of file "${CALL_LOG}" should not include "psql"
    End

    It "fails before requesting a switch when archive-status inspection fails"
      export DATE_EPOCH_OUT=456 PG_WALDUMP_OUT="transaction record" FIND_EXIT=17
      When call switch_and_report_checkpoint
      The status should be failure
      The output should include "failed to inspect WAL archive status before switch"
      The output should not include "timed out waiting for switched WAL"
      The output should include "switch-checkpoint=123"
      The contents of file "${CALL_LOG}" should not include "select pg_switch_wal()"
    End

    It "fails while confirming a switch when archive-status inspection fails"
      export DATE_EPOCH_OUT=456 PG_WALDUMP_OUT="transaction record" FIND_FAIL_ON_CALL=2
      When call switch_and_report_checkpoint
      The status should be failure
      The output should include "failed to inspect WAL archive status after switch"
      The output should not include "timed out waiting for switched WAL"
      The output should include "switch-checkpoint=123"
      The contents of file "${CALL_LOG}" should include "select pg_switch_wal()"
    End

    It "fails before throttle evaluation when the current time cannot be read"
      export DATE_EPOCH_EXIT=17
      When call switch_and_report_checkpoint
      The status should be failure
      The output should include "failed to determine current time for WAL switch"
      The output should include "switch-checkpoint=123"
      The contents of file "${CALL_LOG}" should not include "psql"
    End

    It "fails without advancing the checkpoint when the switch request fails"
      export DATE_EPOCH_OUT=456 PG_WALDUMP_OUT="transaction record"
      export PG_WALDUMP_EXIT=17 PSQL_FAIL_ON_CALL=2 PSQL_EXIT=17
      When call switch_and_report_checkpoint
      The status should be failure
      The output should include "pg_switch_wal failed, will retry on the next round"
      The output should include "switch-checkpoint=123"
    End

    It "fails without advancing the checkpoint when the current WAL lookup fails"
      export DATE_EPOCH_OUT=456 PSQL_FAIL_ON_CALL=1 PSQL_EXIT=17
      When call switch_and_report_checkpoint
      The status should be failure
      The error should include "failed to resolve current WAL for switch"
      The output should include "switch-checkpoint=123"
    End

    It "fails without advancing the checkpoint when current WAL analysis has no usable record"
      export DATE_EPOCH_OUT=456 PG_WALDUMP_EXIT=17
      When call switch_and_report_checkpoint
      The status should be failure
      The error should include "failed to inspect current WAL for switch: f"
      The output should include "switch-checkpoint=123"
    End

    It "fails without advancing the checkpoint when no ready WAL confirms the switch"
      export DATE_EPOCH_OUT=456 PG_WALDUMP_OUT="transaction record"
      When call switch_and_report_checkpoint
      The status should be failure
      The output should include "timed out waiting for switched WAL"
      The output should include "switch-checkpoint=123"
    End
  End

  Describe "purge_expired_files()"
    It "fails before expiry arithmetic when the retention clock is not a decimal epoch"
      export DATE_EPOCH_OUT="not-an-epoch" DP_TTL_SECONDS=3600
      When call purge_and_report_checkpoint
      The status should be failure
      The output should include "failed to determine current time for WAL retention"
      The output should include "purge-checkpoint=123"
      The contents of file "${CALL_LOG}" should not include "datasafed"
    End

    It "fails before expiry arithmetic when the retention clock cannot be read"
      export DATE_EPOCH_EXIT=17 DP_TTL_SECONDS=3600
      When call purge_and_report_checkpoint
      The status should be failure
      The output should include "failed to determine current time for WAL retention"
      The output should include "purge-checkpoint=123"
      The contents of file "${CALL_LOG}" should not include "datasafed"
    End

    It "fails without advancing the checkpoint when the expired-WAL listing fails"
      export DP_TTL_SECONDS=3600 DATASAFED_LIST_EXIT=17
      When call purge_and_report_checkpoint
      The status should be failure
      The error should include "failed to list expired WAL files"
      The output should include "purge-checkpoint=123"
      The path "${DP_BACKUP_INFO_FILE}" should not be exist
    End

    It "advances the checkpoint when a successful expiration scan finds no files"
      export DATE_EPOCH_OUT=1000 DP_TTL_SECONDS=3600 DATASAFED_LIST_OUT=""
      When call purge_and_report_checkpoint
      The status should eq 0
      The output should include "purge-checkpoint=1000"
      The contents of file "${CALL_LOG}" should include "datasafed list -f --recursive --older-than"
      The contents of file "${CALL_LOG}" should not include "datasafed stat"
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
    It "does not upload past a ready marker whose WAL file is missing"
      missing_wal="000000010000000000000001"
      newer_wal="000000010000000000000002"
      touch "${LOG_DIR}/${newer_wal}"
      touch -t 202608160000.00 "${LOG_DIR}/archive_status/${missing_wal}.ready"
      touch -t 202608160001.00 "${LOG_DIR}/archive_status/${newer_wal}.ready"
      When call upload_wal_log
      The status should eq 0
      The output should include "local WAL file ${missing_wal} is missing, keeping ${missing_wal}.ready for retry"
      The contents of file "${CALL_LOG}" should not include "datasafed push -z zstd ${newer_wal}"
      The path "${LOG_DIR}/archive_status/${missing_wal}.ready" should be exist
      The path "${LOG_DIR}/archive_status/${newer_wal}.ready" should be exist
      The path "${LOG_DIR}/archive_status/${newer_wal}.done" should not be exist
    End

    It "fails before pushing when archive-status enumeration fails"
      wal_name="000000010000000000000001"
      touch "${LOG_DIR}/${wal_name}"
      touch "${LOG_DIR}/archive_status/${wal_name}.ready"
      export LS_EXIT=17
      When call upload_wal_log
      The status should be failure
      The output should include "failed to list WAL archive status"
      The contents of file "${CALL_LOG}" should include "ls -tr ./archive_status/"
      The contents of file "${CALL_LOG}" should not include "datasafed push"
      The path "${LOG_DIR}/archive_status/${wal_name}.ready" should be exist
    End

    It "stops before later WALs when the archive-status commit fails"
      first_wal="000000010000000000000001"
      second_wal="000000010000000000000002"
      touch "${LOG_DIR}/${first_wal}" "${LOG_DIR}/${second_wal}"
      touch -t 202608160000.00 "${LOG_DIR}/archive_status/${first_wal}.ready"
      touch -t 202608160001.00 "${LOG_DIR}/archive_status/${second_wal}.ready"
      export MV_FAIL_SOURCE="./archive_status/${first_wal}.ready"
      export PG_WALDUMP_OUT='rmgr: Transaction desc: COMMIT 2026-08-16T00:00:00Z; origin: node'
      export DATE_D_OUT="2026-08-16T00:00:00Z"
      When call upload_and_report_stop_time
      The status should be failure
      The output should include "failed to mark ${first_wal} done, keeping ${first_wal}.ready for retry"
      The output should include "stop-time=2026-08-16T00:00:00Z"
      The contents of file "${CALL_LOG}" should include "datasafed push -z zstd ${first_wal}"
      The contents of file "${CALL_LOG}" should not include "datasafed push -z zstd ${second_wal}"
      The path "${LOG_DIR}/archive_status/${first_wal}.ready" should be exist
      The path "${LOG_DIR}/archive_status/${first_wal}.done" should not be exist
      The path "${LOG_DIR}/archive_status/${second_wal}.ready" should be exist
      The path "${LOG_DIR}/archive_status/${second_wal}.done" should not be exist
    End

    It "fails before pushing when the archive partition cannot be generated"
      wal_name="000000010000000000000001"
      touch "${LOG_DIR}/${wal_name}"
      touch "${LOG_DIR}/archive_status/${wal_name}.ready"
      export DATE_TODAY_EXIT=17
      When call upload_wal_log
      The status should be failure
      The output should include "failed to determine WAL upload partition"
      The contents of file "${CALL_LOG}" should not include "datasafed push"
      The path "${LOG_DIR}/archive_status/${wal_name}.ready" should be exist
      The path "${LOG_DIR}/archive_status/${wal_name}.done" should not be exist
    End

    It "fails before pushing when the archive partition is malformed"
      wal_name="000000010000000000000001"
      touch "${LOG_DIR}/${wal_name}"
      touch "${LOG_DIR}/archive_status/${wal_name}.ready"
      export DATE_TODAY_OUT="../invalid"
      When call upload_wal_log
      The status should be failure
      The output should include "failed to determine WAL upload partition"
      The contents of file "${CALL_LOG}" should not include "datasafed"
      The path "${LOG_DIR}/archive_status/${wal_name}.ready" should be exist
      The path "${LOG_DIR}/archive_status/${wal_name}.done" should not be exist
    End

    It "keeps the WAL retryable when analysis fails without a usable COMMIT"
      wal_name="000000010000000000000001"
      touch "${LOG_DIR}/${wal_name}"
      touch "${LOG_DIR}/archive_status/${wal_name}.ready"
      export PG_WALDUMP_EXIT=17
      When call upload_and_report_stop_time
      The status should eq 0
      The output should include "failed to inspect ${wal_name} for stop time, keeping ${wal_name}.ready for retry"
      The output should include "stop-time=2026-08-15T23:59:00Z"
      The contents of file "${CALL_LOG}" should not include "datasafed push"
      The path "${LOG_DIR}/archive_status/${wal_name}.ready" should be exist
      The path "${LOG_DIR}/archive_status/${wal_name}.done" should not be exist
    End

    It "accepts a usable COMMIT from a partial-WAL analysis failure"
      wal_name="000000010000000000000001"
      touch "${LOG_DIR}/${wal_name}"
      touch "${LOG_DIR}/archive_status/${wal_name}.ready"
      export PG_WALDUMP_EXIT=17
      export PG_WALDUMP_OUT='rmgr: Transaction desc: COMMIT 2026-08-16T00:00:00Z; origin: node'
      export DATE_D_OUT="2026-08-16T00:00:00Z"
      When call upload_and_report_stop_time
      The status should eq 0
      The output should include "stop-time=2026-08-16T00:00:00Z"
      The contents of file "${CALL_LOG}" should include "datasafed push -z zstd ${wal_name}"
      The path "${LOG_DIR}/archive_status/${wal_name}.done" should be exist
      The path "${LOG_DIR}/archive_status/${wal_name}.ready" should not be exist
    End

    It "keeps the WAL retryable when its stop time cannot be normalized"
      wal_name="000000010000000000000001"
      touch "${LOG_DIR}/${wal_name}"
      touch "${LOG_DIR}/archive_status/${wal_name}.ready"
      export PG_WALDUMP_OUT='rmgr: Transaction desc: COMMIT invalid-time; origin: node'
      export DATE_D_OUT="unused" DATE_D_EXIT=17
      When call upload_and_report_stop_time
      The status should eq 0
      The output should include "failed to normalize stop time for ${wal_name}, keeping ${wal_name}.ready for retry"
      The output should include "stop-time=2026-08-15T23:59:00Z"
      The contents of file "${CALL_LOG}" should not include "datasafed push"
      The path "${LOG_DIR}/archive_status/${wal_name}.ready" should be exist
      The path "${LOG_DIR}/archive_status/${wal_name}.done" should not be exist
    End

    It "does not upload or publish past the first failed WAL segment"
      first_wal="000000010000000000000001"
      second_wal="000000010000000000000002"
      touch "${LOG_DIR}/${first_wal}" "${LOG_DIR}/${second_wal}"
      touch -t 202608160000.00 "${LOG_DIR}/archive_status/${first_wal}.ready"
      touch -t 202608160001.00 "${LOG_DIR}/archive_status/${second_wal}.ready"
      export DATASAFED_PUSH_FAIL_WAL="${first_wal}"
      export PG_WALDUMP_OUT='rmgr: Transaction desc: COMMIT 2026-08-16T00:01:00Z; origin: node'
      export DATE_D_OUT="2026-08-16T00:01:00Z"
      When call upload_and_report_stop_time
      The status should eq 0
      The output should include "stop-time=2026-08-15T23:59:00Z"
      The contents of file "${CALL_LOG}" should include "datasafed push -z zstd ${first_wal}"
      The contents of file "${CALL_LOG}" should not include "datasafed push -z zstd ${second_wal}"
      The path "${LOG_DIR}/archive_status/${first_wal}.ready" should be exist
      The path "${LOG_DIR}/archive_status/${second_wal}.ready" should be exist
    End

    It "does not advance the metadata stop time when the upload fails"
      wal_name="000000010000000000000001"
      touch "${LOG_DIR}/${wal_name}"
      touch "${LOG_DIR}/archive_status/${wal_name}.ready"
      export PG_WALDUMP_OUT='rmgr: Transaction desc: COMMIT 2026-08-16T00:00:00Z; origin: node'
      export DATE_D_OUT="2026-08-16T00:00:00Z" DATASAFED_PUSH_EXIT=17
      When call upload_and_report_stop_time
      The status should eq 0
      The output should include "stop-time=2026-08-15T23:59:00Z"
    End

    It "advances the metadata stop time after a successful upload"
      wal_name="000000010000000000000001"
      touch "${LOG_DIR}/${wal_name}"
      touch "${LOG_DIR}/archive_status/${wal_name}.ready"
      export PG_WALDUMP_OUT='rmgr: Transaction desc: COMMIT 2026-08-16T00:00:00Z; origin: node'
      export DATE_D_OUT="2026-08-16T00:00:00Z"
      When call upload_and_report_stop_time
      The status should eq 0
      The output should include "stop-time=2026-08-16T00:00:00Z"
    End

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
    It "fails before metadata work when local archive-status listing is unavailable"
      export FIND_EXIT=17
      When call uploadMissingLogs
      The status should be failure
      The output should include "failed to list local WAL archive status"
      The contents of file "${CALL_LOG}" should include "find ./archive_status -type f"
      The contents of file "${CALL_LOG}" should not include "datasafed stat"
      The contents of file "${CALL_LOG}" should not include "datasafed push"
    End

    It "fails before repository access when the archive partition cannot be generated"
      wal_name="000000010000000000000001"
      touch "${LOG_DIR}/${wal_name}"
      touch "${LOG_DIR}/archive_status/${wal_name}.done"
      export DATE_TODAY_EXIT=17
      When call uploadMissingLogs
      The status should be failure
      The output should include "failed to determine missing-WAL upload partition"
      The contents of file "${CALL_LOG}" should not include "datasafed"
      The path "${LOG_DIR}/archive_status/${wal_name}.done" should be exist
      The path "${DP_BACKUP_INFO_FILE}" should not be exist
    End

    It "fails before repository access when the reconciliation partition is malformed"
      wal_name="000000010000000000000001"
      touch "${LOG_DIR}/${wal_name}"
      touch "${LOG_DIR}/archive_status/${wal_name}.done"
      export DATE_TODAY_OUT="../invalid"
      When call uploadMissingLogs
      The status should be failure
      The output should include "failed to determine missing-WAL upload partition"
      The contents of file "${CALL_LOG}" should not include "datasafed"
      The path "${LOG_DIR}/archive_status/${wal_name}.done" should be exist
    End

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

    It "does not reconcile past the first failed WAL upload"
      older_wal="000000010000000000000001"
      newer_wal="000000010000000000000002"
      export DATASAFED_LIST_OUT='[{"path":"/20260816/000000010000000000000000.zst","mtime":"2026-08-16T00:00:00Z"}]'
      export DATASAFED_PUSH_FAIL_WAL="${older_wal}"
      touch "${LOG_DIR}/${older_wal}" "${LOG_DIR}/${newer_wal}"
      touch "${LOG_DIR}/archive_status/${older_wal}.done" \
        "${LOG_DIR}/archive_status/${newer_wal}.done"
      When call uploadMissingLogs
      The status should be failure
      The output should include "failed to upload ${older_wal}, will retry reconciliation"
      The contents of file "${CALL_LOG}" should include "datasafed push -z zstd ${older_wal}"
      The contents of file "${CALL_LOG}" should not include "datasafed push -z zstd ${newer_wal}"
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

    It "does not reconcile past the first WAL whose local source is missing"
      older_wal="000000010000000000000001"
      newer_wal="000000010000000000000002"
      export DATASAFED_LIST_OUT='[{"path":"/20260816/000000010000000000000000.zst","mtime":"2026-08-16T00:00:00Z"}]'
      touch "${LOG_DIR}/${newer_wal}"
      touch "${LOG_DIR}/archive_status/${older_wal}.done" \
        "${LOG_DIR}/archive_status/${newer_wal}.done"
      When call uploadMissingLogs
      The status should be failure
      The output should include "cannot reconcile ${older_wal}: local WAL file is missing"
      The contents of file "${CALL_LOG}" should not include "datasafed push -z zstd ${newer_wal}"
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

    It "fails before pulling when the oldest-WAL workdir cannot be prepared"
      blocked_workdir="${tmpdir}/blocked-workdir"
      printf 'not a directory\n' > "${blocked_workdir}"
      KB_BACKUP_WORKDIR="${blocked_workdir}"
      export DATASAFED_STAT_OUT="TotalSize: 4096"
      export DATASAFED_LIST_OUT='[{"path":"/20260816/000000010000000000000001.zst","mtime":"2026-08-16T00:00:00Z"}]'
      When call save_backup_status
      The status should be failure
      The error should include "failed to prepare oldest WAL workdir"
      The result of function call_log should not include "datasafed pull "
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
      The path "${KB_BACKUP_WORKDIR}/dp_oldest_file.info" should not be exist
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
