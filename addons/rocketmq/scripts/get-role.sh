#!/bin/bash

# Traditional HA writes brokerRole once in broker-setup.sh (brokerId 0 =>
# ASYNC_MASTER, otherwise SLAVE). That file is authoritative there.
#
# DLedger does not write brokerRole. The elected leader is SYNC_MASTER and
# followers are SLAVE, and that changes at runtime, so the role has to come
# from GET_BROKER_CONFIG (request code 26).
#
# A missing role must not default to master. That labeled every scaled-out
# replica as master when ACL made the response larger than curl's read window
# (apecloud/apecloud#21787). Exit non-zero instead so the previous label stays.

conf="${DATA_DIR:-/home/rocketmq/store}/broker.conf"
if [ ! -f "$conf" ]; then
    echo "broker.conf not found: $conf" >&2
    exit 1
fi

report_role() {
    case "$1" in
        SLAVE)
            echo -n "slave"
            ;;
        ASYNC_MASTER|SYNC_MASTER)
            echo -n "master"
            ;;
        *)
            echo "unknown brokerRole: ${1:-<empty>}" >&2
            exit 1
            ;;
    esac
}

dledger=$(grep -E '^enableDLegerCommitLog=' "$conf" | tail -n 1 | cut -d= -f2 | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
if [ "$dledger" != "true" ]; then
    report_role "$(grep -E '^brokerRole=' "$conf" | tail -n 1 | cut -d= -f2 | tr -d '[:space:]')"
    exit 0
fi

if [ -z "${BROKER_PORT:-}" ]; then
    echo "BROKER_PORT is empty" >&2
    exit 1
fi

build_request() {
    local json_header="$1"
    local header_len=${#json_header}
    local frame_size=$((4 + header_len))
    local binary=""
    local i char ascii

    binary+="\\x$(printf %08x "$frame_size" | cut -c1-2)"
    binary+="\\x$(printf %08x "$frame_size" | cut -c3-4)"
    binary+="\\x$(printf %08x "$frame_size" | cut -c5-6)"
    binary+="\\x$(printf %08x "$frame_size" | cut -c7-8)"
    binary+="\\x00"
    binary+="\\x$(printf %06x "$header_len" | cut -c1-2)"
    binary+="\\x$(printf %06x "$header_len" | cut -c3-4)"
    binary+="\\x$(printf %06x "$header_len" | cut -c5-6)"
    for (( i=0; i<header_len; i++ )); do
        char="${json_header:$i:1}"
        ascii=$(printf "%d" "'$char")
        binary+="\\x$(printf %02x "$ascii")"
    done
    printf '%s' "$binary"
}

if [ "${ENABLE_ACL:-false}" = "true" ]; then
    if [ -z "${ROCKETMQ_USER:-}" ] || [ -z "${ROCKETMQ_PASSWORD:-}" ]; then
        echo "ACL credentials are empty" >&2
        exit 1
    fi
    sig=$(printf '%s' "$ROCKETMQ_USER" | openssl dgst -sha1 -hmac "$ROCKETMQ_PASSWORD" -binary | base64)
    json_header='{"code":26,"language":"GO","version":317,"opaque":1,"flag":0,"remark":"","extFields":{"Signature":"'"$sig"'","AccessKey":"'"$ROCKETMQ_USER"'"}}'
else
    json_header='{"code":26,"language":"GO","version":317,"opaque":1,"flag":0,"remark":"","extFields":{}}'
fi

# curl --max-time waits for the broker to close the connection, which it does
# not. awk exits as soon as brokerRole appears, and that closes the pipe.
role=$(echo -e "$(build_request "$json_header")" | curl --silent --no-buffer --max-time 2 "telnet://127.0.0.1:${BROKER_PORT}" | tr -d '\0' | awk 'match($0, /brokerRole=[^ ]+/) { split(substr($0, RSTART, RLENGTH), parts, "="); print parts[2]; exit }')
report_role "$role"
