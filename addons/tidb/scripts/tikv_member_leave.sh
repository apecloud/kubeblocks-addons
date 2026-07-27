#!/bin/bash

set -eo pipefail

# shellcheck source=common.sh
# shellcheck disable=SC1091
. "${TIDB_SCRIPTS_DIR:-/scripts}/common.sh"

tikv_member_leave_diagnose_not_ready() {
    local phase="$1"
    local context="$2"
    local retry_safe="$3"
    {
        echo "tikv memberLeave diagnosis:"
        echo "  action: tikv-member-leave"
        echo "  phase: $phase"
        echo "  target: ${TIKV_ADDRESS:-<unset>}"
        echo "  $context"
        echo "  next-retry-safe: $retry_safe"
    } >&2
}

pd_ctl() {
    # shellcheck disable=SC2086,SC2154
    /pd-ctl -u "$scheme://$PD_ADDRESS" $extraArg "$@"
}

read_store_state() {
    local output
    local state

    if ! output=$(pd_ctl store); then
        tikv_member_leave_diagnose_not_ready \
            "store-probe-failed" "pd-ctl could not list stores" "no"
        return 1
    fi

    if ! state=$(printf '%s\n' "$output" | jq -er --arg address "$TIKV_ADDRESS" \
        '[.stores[]? | select(.store.address == $address) | .store.state_name][0] // "Absent"'); then
        tikv_member_leave_diagnose_not_ready \
            "store-probe-invalid" "pd-ctl returned an invalid store document" "no"
        return 1
    fi

    printf '%s\n' "$state"
}

delete_store() {
    local output

    if ! output=$(pd_ctl store delete addr "$TIKV_ADDRESS" 2>&1); then
        tikv_member_leave_diagnose_not_ready \
            "delete-rejected" "pd-ctl rejected store deletion: $output" "no"
        return 1
    fi
    if [ "$output" != "Success!" ]; then
        tikv_member_leave_diagnose_not_ready \
            "delete-rejected" "unexpected delete response: $output" "no"
        return 1
    fi
}

remove_tombstone() {
    local output

    if ! output=$(pd_ctl store remove-tombstone 2>&1); then
        tikv_member_leave_diagnose_not_ready \
            "remove-tombstone-rejected" "pd-ctl rejected tombstone removal: $output" "no"
        return 1
    fi
    if [ "$output" != "Success!" ]; then
        tikv_member_leave_diagnose_not_ready \
            "remove-tombstone-rejected" "unexpected remove-tombstone response: $output" "no"
        return 1
    fi
}

run_tikv_member_leave() {
    local state

    if [ -z "${KB_LEAVE_MEMBER_POD_FQDN:-}" ]; then
        tikv_member_leave_diagnose_not_ready \
            "invalid-input" "KB_LEAVE_MEMBER_POD_FQDN is empty" "no"
        return 1
    fi
    if [ -z "${PD_ADDRESS:-}" ]; then
        tikv_member_leave_diagnose_not_ready \
            "invalid-input" "PD_ADDRESS is empty" "no"
        return 1
    fi

    set_component_tls_variables
    TIKV_ADDRESS="${KB_LEAVE_MEMBER_POD_FQDN}:20160"

    if ! state=$(read_store_state); then
        return 1
    fi

    case "$state" in
        Absent)
            echo "tikv store $TIKV_ADDRESS is already absent"
            return 0
            ;;
        Up)
            if ! delete_store; then
                return 1
            fi
            if ! state=$(read_store_state); then
                return 1
            fi
            ;;
        Offline|Tombstone)
            ;;
        *)
            tikv_member_leave_diagnose_not_ready \
                "store-state-invalid" "unexpected store state: $state" "no"
            return 1
            ;;
    esac

    case "$state" in
        Absent)
            echo "member leave success"
            return 0
            ;;
        Offline)
            tikv_member_leave_diagnose_not_ready \
                "store-offline" "store is draining regions" "yes"
            return 1
            ;;
        Tombstone)
            if ! remove_tombstone; then
                return 1
            fi
            if ! state=$(read_store_state); then
                return 1
            fi
            if [ "$state" = "Absent" ]; then
                echo "member leave success"
                return 0
            fi
            tikv_member_leave_diagnose_not_ready \
                "tombstone-still-present" "store state after removal: $state" "yes"
            return 1
            ;;
        *)
            tikv_member_leave_diagnose_not_ready \
                "store-state-invalid" "unexpected store state after deletion: $state" "no"
            return 1
            ;;
    esac
}

# This is magic for shellspec. The production action executes the function;
# shellspec only sources the definitions.
${__SOURCED__:+false} : || return 0

run_tikv_member_leave
