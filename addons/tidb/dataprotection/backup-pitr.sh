#!/bin/bash

PITR_TERMINATION_REQUESTED=false

function run_br() {
    /br "$@"
}

function get_log_backup_status() {
    # shellcheck disable=SC2086
    run_br log status --task-name=pitr --pd "$PD_ADDRESS" $EXTRA_ARGS
}

function normalize_utc_time() {
    date -d "$1" -u '+%Y-%m-%dT%H:%M:%SZ'
}

function get_backup_total_size() {
    datasafed stat / | awk '/TotalSize/ {print $2; exit}'
}

function save_backup_status() {
    local res start_time_str checkpoint_time_str start_time checkpoint_time total_size

    if ! res=$(get_log_backup_status); then
        echo "ERROR: failed to query TiDB log backup status" >&2
        return 1
    fi

    start_time_str=$(printf '%s\n' "$res" | awk -F': ' '/^[[:space:]]*start:/ {print $2; exit}')
    checkpoint_time_str=$(printf '%s\n' "$res" | awk -F': ' '/^[[:space:]]*checkpoint\[global\]:/ {print $2; exit}' | cut -d';' -f1)
    if [ -z "$start_time_str" ] || [ -z "$checkpoint_time_str" ]; then
        echo "ERROR: log backup status is missing start or global checkpoint" >&2
        return 1
    fi

    if ! start_time=$(normalize_utc_time "$start_time_str"); then
        echo "ERROR: invalid log backup start time: $start_time_str" >&2
        return 1
    fi
    if ! checkpoint_time=$(normalize_utc_time "$checkpoint_time_str"); then
        echo "ERROR: invalid log backup checkpoint time: $checkpoint_time_str" >&2
        return 1
    fi
    if ! total_size=$(get_backup_total_size) || [ -z "$total_size" ]; then
        echo "ERROR: failed to read log backup size" >&2
        return 1
    fi

    echo "start_time: $start_time, checkpoint_time: $checkpoint_time, total_size: $total_size"
    DP_save_backup_status_info "$total_size" "$start_time" "$checkpoint_time" "" ""
}

function save_backup_status_with_retry() {
    local attempts="${PITR_STATUS_RETRY_ATTEMPTS:-3}"
    local interval="${PITR_STATUS_RETRY_INTERVAL_SECONDS:-2}"
    local attempt=1

    case "$attempts" in
        ''|*[!0-9]*|0)
            echo "ERROR: PITR_STATUS_RETRY_ATTEMPTS must be a positive integer" >&2
            return 2
            ;;
    esac
    case "$interval" in
        ''|*[!0-9]*)
            echo "ERROR: PITR_STATUS_RETRY_INTERVAL_SECONDS must be a non-negative integer" >&2
            return 2
            ;;
    esac

    while [ "$attempt" -le "$attempts" ]; do
        if save_backup_status; then
            return 0
        fi
        echo "WARN: log backup status attempt $attempt/$attempts failed" >&2
        if [ "$attempt" -lt "$attempts" ]; then
            sleep "$interval"
        fi
        attempt=$((attempt + 1))
    done

    echo "ERROR: log backup status failed after $attempts attempts" >&2
    return 1
}

function start_log_backup() {
    # shellcheck disable=SC2086
    run_br log start --task-name=pitr --pd "$PD_ADDRESS" --storage "s3://$BUCKET$DP_BACKUP_BASE_PATH?access-key=$ACCESS_KEY_ID&secret-access-key=$SECRET_ACCESS_KEY" --s3.endpoint "$ENDPOINT" $BR_EXTRA_ARGS
}

function stop_log_backup() {
    # shellcheck disable=SC2086
    run_br log stop --task-name=pitr --pd "$PD_ADDRESS" --storage "s3://$BUCKET$DP_BACKUP_BASE_PATH?access-key=$ACCESS_KEY_ID&secret-access-key=$SECRET_ACCESS_KEY" --s3.endpoint "$ENDPOINT" $EXTRA_ARGS
}

function ensure_log_backup_started() {
    local status_rc

    if save_backup_status_with_retry; then
        echo "INFO: attached to existing TiDB log backup task"
        return 0
    else
        status_rc=$?
    fi
    if [ "$status_rc" -eq 2 ]; then
        return "$status_rc"
    fi

    echo "INFO: no usable TiDB log backup task status; starting task"
    if ! start_log_backup; then
        echo "ERROR: failed to start TiDB log backup task" >&2
        return 1
    fi
    return 0
}

function finish_log_backup() {
    local exit_code="$1"
    local termination_requested="${2:-false}"

    if [ "$termination_requested" = "true" ]; then
        save_backup_status_with_retry || echo "WARN: final log backup status could not be saved" >&2
        if ! stop_log_backup; then
            echo "ERROR: failed to stop TiDB log backup task during explicit termination" >&2
            [ "$exit_code" -eq 0 ] && exit_code=1
        fi
    elif [ "$exit_code" -ne 0 ]; then
        echo "ERROR: PITR monitor failed with exit code $exit_code; preserving the log backup task" >&2
    else
        echo "INFO: PITR monitor exited without an explicit termination request; preserving the log backup task" >&2
    fi

    return "$exit_code"
}

function handle_termination() {
    PITR_TERMINATION_REQUESTED=true
    exit 0
}

function handle_exit() {
    local exit_code=$?
    local final_exit_code

    trap - EXIT TERM INT
    set +e
    finish_log_backup "$exit_code" "$PITR_TERMINATION_REQUESTED"
    final_exit_code=$?
    exit "$final_exit_code"
}

function main() {
    setStorageVar
    ensure_log_backup_started

    set +x
    while true; do
        save_backup_status_with_retry || return $?
        sleep "${PITR_STATUS_INTERVAL_SECONDS:-20}"
    done
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

trap handle_exit EXIT
trap handle_termination TERM INT
main "$@"
