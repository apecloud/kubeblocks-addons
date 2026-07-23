# shellcheck shell=bash
# shellcheck disable=SC2034,SC2317,SC2329

Describe "TiDB continuous backup PITR monitor"
  __SOURCED__=1
  Include "${PITR_SCRIPT_PATH:-../dataprotection/backup-pitr.sh}"
  unset __SOURCED__

  setup() {
    export PITR_STATUS_RETRY_ATTEMPTS=3
    export PITR_STATUS_RETRY_INTERVAL_SECONDS=0
    export PD_ADDRESS="tidb-pd.default.svc:2379"
    export EXTRA_ARGS=""
    export BR_EXTRA_ARGS=""
    export BUCKET="bucket"
    export DP_BACKUP_BASE_PATH="/continuous"
    export ACCESS_KEY_ID="access"
    export SECRET_ACCESS_KEY="secret"
    export ENDPOINT="http://minio:9000"

    STATUS_MODE="success"
    START_RC=0
    TOTAL_SIZE="128"
    TEST_LEDGER="${SHELLSPEC_TMPBASE}/backup-pitr-ledger-${SHELLSPEC_SPECFILE_ID}"
    TEST_STATUS_COUNT="${TEST_LEDGER}.status-count"
    : > "${TEST_LEDGER}"
    printf '0\n' > "${TEST_STATUS_COUNT}"

    run_br() {
      printf 'br %s\n' "$*" >> "${TEST_LEDGER}"
      case "$1 $2" in
        "log status")
          local count
          count=$(cat "${TEST_STATUS_COUNT}")
          count=$((count + 1))
          printf '%s\n' "${count}" > "${TEST_STATUS_COUNT}"
          if [ "${STATUS_MODE}" = "always-fail" ] ||
             { [ "${STATUS_MODE}" = "transient" ] && [ "${count}" -eq 1 ]; } ||
             { [ "${STATUS_MODE}" = "attach-then-fail" ] && [ "${count}" -gt 1 ]; }; then
            echo "[PD:client:ErrClientGetTSO] get TSO failed, tso client is nil" >&2
            return 1
          fi
          case "${STATUS_MODE}" in
            malformed)
              echo "start: 2026-07-23 00:00:00 +0000"
              return 0
              ;;
            invalid-start)
              cat <<'STATUS'
    start: not-a-time
    checkpoint[global]: 2026-07-23 00:05:00 +0000; gap=1m
STATUS
              return 0
              ;;
            invalid-checkpoint)
              cat <<'STATUS'
    start: 2026-07-23 00:00:00 +0000
    checkpoint[global]: not-a-time; gap=1m
STATUS
              return 0
              ;;
            inverted-range)
              cat <<'STATUS'
    start: 2026-07-23 00:05:00 +0000
    checkpoint[global]: 2026-07-23 00:00:00 +0000; gap=1m
STATUS
              return 0
              ;;
            fractional)
              cat <<'STATUS'
    start: 2026-07-23 00:00:00.123456789 +0000
    checkpoint[global]: 2026-07-23 00:05:00.987654321 +0000; gap=1m
STATUS
              return 0
              ;;
          esac
          cat <<'STATUS'
              start: 2026-07-23 00:00:00 +0000
    checkpoint[global]: 2026-07-23 00:05:00 +0000; gap=1m
STATUS
          ;;
        "log start")
          return "${START_RC}"
          ;;
        "log stop")
          return 0
          ;;
      esac
    }

    normalize_utc_time() {
      case "$1" in
        "2026-07-23 00:00:00 +0000") echo "2026-07-23T00:00:00Z" ;;
        "2026-07-23 00:05:00 +0000") echo "2026-07-23T00:05:00Z" ;;
        "2026-07-23 00:00:00.123456789 +0000") echo "2026-07-23T00:00:00Z" ;;
        "2026-07-23 00:05:00.987654321 +0000") echo "2026-07-23T00:05:00Z" ;;
        *) return 1 ;;
      esac
    }

    get_backup_total_size() {
      echo "${TOTAL_SIZE}"
    }

    DP_save_backup_status_info() {
      printf 'save %s\n' "$*" >> "${TEST_LEDGER}"
    }

    sleep() {
      printf 'sleep %s\n' "$*" >> "${TEST_LEDGER}"
    }

    setStorageVar() {
      :
    }
  }

  BeforeEach 'setup'

  ledger_count() {
    local pattern="$1"
    grep -c "${pattern}" "${TEST_LEDGER}" 2>/dev/null || true
  }

  run_transient_status_case() {
    STATUS_MODE="transient"
    save_backup_status_with_retry
    local rc=$?
    echo "status_calls=$(ledger_count '^br log status')"
    echo "save_calls=$(ledger_count '^save ')"
    echo "stop_calls=$(ledger_count '^br log stop')"
    return "${rc}"
  }

  It "retries one transient status failure without stopping the log task"
    When call run_transient_status_case
    The status should be success
    The stdout should include "status_calls=2"
    The stdout should include "save_calls=1"
    The stdout should include "stop_calls=0"
    The stderr should include "status attempt 1/3 failed"
  End

  run_exhausted_status_case() {
    STATUS_MODE="always-fail"
    save_backup_status_with_retry
    local rc=$?
    echo "status_calls=$(ledger_count '^br log status')"
    echo "save_calls=$(ledger_count '^save ')"
    echo "stop_calls=$(ledger_count '^br log stop')"
    return "${rc}"
  }

  It "fails after a bounded number of status attempts without stopping the log task"
    When call run_exhausted_status_case
    The status should be failure
    The stdout should include "status_calls=3"
    The stdout should include "save_calls=0"
    The stdout should include "stop_calls=0"
    The stderr should include "status failed after 3 attempts"
  End

  run_attach_case() {
    ensure_log_backup_started
    local rc=$?
    echo "status_calls=$(ledger_count '^br log status')"
    echo "start_calls=$(ledger_count '^br log start')"
    return "${rc}"
  }

  It "attaches to an existing log task without starting a replacement"
    When call run_attach_case
    The status should be success
    The stdout should include "status_calls=1"
    The stdout should include "start_calls=0"
  End

  run_start_case() {
    STATUS_MODE="always-fail"
    ensure_log_backup_started
    local rc=$?
    echo "status_calls=$(ledger_count '^br log status')"
    echo "start_calls=$(ledger_count '^br log start')"
    return "${rc}"
  }

  It "starts a task only after bounded status checks find no usable task"
    When call run_start_case
    The status should be success
    The stdout should include "status_calls=3"
    The stdout should include "start_calls=1"
    The stderr should include "status failed after 3 attempts"
  End

  run_start_failure_case() {
    STATUS_MODE="always-fail"
    START_RC=1
    ensure_log_backup_started
    local rc=$?
    echo "start_calls=$(ledger_count '^br log start')"
    echo "stop_calls=$(ledger_count '^br log stop')"
    return "${rc}"
  }

  It "fails closed when neither attach nor start succeeds"
    When call run_start_failure_case
    The status should be failure
    The stdout should include "start_calls=1"
    The stdout should include "stop_calls=0"
    The stderr should include "failed to start TiDB log backup task"
  End

  run_invalid_retry_config_case() {
    PITR_STATUS_RETRY_ATTEMPTS="invalid"
    ensure_log_backup_started
    local rc=$?
    echo "status_calls=$(ledger_count '^br log status')"
    echo "start_calls=$(ledger_count '^br log start')"
    return "${rc}"
  }

  It "does not start a task when retry configuration is invalid"
    When call run_invalid_retry_config_case
    The status should equal 2
    The stdout should include "status_calls=0"
    The stdout should include "start_calls=0"
    The stderr should include "must be a positive integer"
  End

  run_empty_retry_config_case() {
    local field="$1"
    if [ "${field}" = "attempts" ]; then
      PITR_STATUS_RETRY_ATTEMPTS=""
    else
      PITR_STATUS_RETRY_INTERVAL_SECONDS=""
    fi
    ensure_log_backup_started
    local rc=$?
    echo "status_calls=$(ledger_count '^br log status')"
    echo "start_calls=$(ledger_count '^br log start')"
    return "${rc}"
  }

  It "rejects an explicitly empty retry-attempt count before probing or starting"
    When call run_empty_retry_config_case attempts
    The status should equal 2
    The stdout should include "status_calls=0"
    The stdout should include "start_calls=0"
    The stderr should include "must be a positive integer"
  End

  It "rejects an explicitly empty retry interval before probing or starting"
    When call run_empty_retry_config_case interval
    The status should equal 2
    The stdout should include "status_calls=0"
    The stdout should include "start_calls=0"
    The stderr should include "must be a non-negative integer"
  End

  run_unset_retry_config_case() {
    unset PITR_STATUS_RETRY_ATTEMPTS PITR_STATUS_RETRY_INTERVAL_SECONDS
    ensure_log_backup_started
    local rc=$?
    echo "status_calls=$(ledger_count '^br log status')"
    echo "start_calls=$(ledger_count '^br log start')"
    return "${rc}"
  }

  It "uses bounded defaults only when retry configuration is absent"
    When call run_unset_retry_config_case
    The status should be success
    The stdout should include "status_calls=1"
    The stdout should include "start_calls=0"
  End

  run_malformed_status_case() {
    STATUS_MODE="malformed"
    save_backup_status
    local rc=$?
    echo "save_calls=$(ledger_count '^save ')"
    return "${rc}"
  }

  It "rejects malformed status instead of overwriting the recoverable range"
    When call run_malformed_status_case
    The status should be failure
    The stdout should include "save_calls=0"
    The stderr should include "missing start or global checkpoint"
  End

  run_status_validation_case() {
    STATUS_MODE="$1"
    TOTAL_SIZE="${2:-128}"
    save_backup_status
    local rc=$?
    echo "save_calls=$(ledger_count '^save ')"
    return "${rc}"
  }

  It "rejects a non-empty invalid start time before writing status"
    When call run_status_validation_case invalid-start
    The status should be failure
    The stdout should include "save_calls=0"
    The stderr should include "invalid log backup start time"
  End

  It "rejects a non-empty invalid checkpoint time before writing status"
    When call run_status_validation_case invalid-checkpoint
    The status should be failure
    The stdout should include "save_calls=0"
    The stderr should include "invalid log backup checkpoint time"
  End

  It "rejects a start time later than the checkpoint before writing status"
    When call run_status_validation_case inverted-range
    The status should be failure
    The stdout should include "save_calls=0"
    The stderr should include "later than checkpoint"
  End

  It "rejects a non-decimal backup size before writing status"
    When call run_status_validation_case success NaN
    The status should be failure
    The stdout should include "save_calls=0"
    The stderr should include "non-negative decimal integer"
  End

  It "rejects a negative backup size before writing status"
    When call run_status_validation_case success -1
    The status should be failure
    The stdout should include "save_calls=0"
    The stderr should include "non-negative decimal integer"
  End

  It "rejects a backup size above the non-negative int64 range before writing status"
    When call run_status_validation_case success 9223372036854775808
    The status should be failure
    The stdout should include "save_calls=0"
    The stderr should include "within int64 range"
  End

  It "accepts a zero backup size"
    When call run_status_validation_case success 0
    The status should be success
    The stdout should include "save_calls=1"
  End

  It "accepts the maximum non-negative int64 backup size"
    When call run_status_validation_case success 9223372036854775807
    The status should be success
    The stdout should include "save_calls=1"
  End

  It "accepts the fractional timestamp shape emitted by BR v8.4"
    When call run_status_validation_case fractional
    The status should be success
    The stdout should include "save_calls=1"
  End

  run_abnormal_exit_case() {
    finish_log_backup 17 false
    local rc=$?
    echo "stop_calls=$(ledger_count '^br log stop')"
    return "${rc}"
  }

  It "preserves the log task on abnormal monitor exit"
    When call run_abnormal_exit_case
    The status should equal 17
    The stdout should include "stop_calls=0"
    The stderr should include "preserving the log backup task"
  End

  run_explicit_termination_case() {
    finish_log_backup 0 true
    local rc=$?
    echo "stop_calls=$(ledger_count '^br log stop')"
    return "${rc}"
  }

  It "stops the log task on explicit monitor termination"
    When call run_explicit_termination_case
    The status should be success
    The stdout should include "stop_calls=1"
  End

  run_main_failure_case() {
    STATUS_MODE="attach-then-fail"
    PITR_STATUS_RETRY_ATTEMPTS=2
    (
      PITR_TERMINATION_REQUESTED=false
      trap handle_exit EXIT
      main
    )
    local rc=$?
    echo "status_calls=$(ledger_count '^br log status')"
    echo "start_calls=$(ledger_count '^br log start')"
    echo "stop_calls=$(ledger_count '^br log stop')"
    return "${rc}"
  }

  It "preserves the task when the real monitor loop exhausts status retries"
    When call run_main_failure_case
    The status should be failure
    The stdout should include "status_calls=3"
    The stdout should include "start_calls=0"
    The stdout should include "stop_calls=0"
    The stderr should include "preserving the log backup task"
  End

  run_termination_trap_case() {
    (
      PITR_TERMINATION_REQUESTED=false
      trap handle_exit EXIT
      handle_termination
    )
    local rc=$?
    echo "stop_calls=$(ledger_count '^br log stop')"
    return "${rc}"
  }

  It "routes explicit termination through the stop path"
    When call run_termination_trap_case
    The status should be success
    The stdout should include "stop_calls=1"
  End
End
