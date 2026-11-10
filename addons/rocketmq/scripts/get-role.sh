#!/bin/bash

# Master/slave role is assigned once in broker-setup.sh and persisted in
# broker.conf (brokerId 0 => ASYNC_MASTER, otherwise SLAVE). Reading that file
# is authoritative for the traditional HA mode.
#
# GET_BROKER_CONFIG over the broker port is not used here. With ACL enabled the
# response is larger than curl's 0.5s telnet read, so brokerRole is often
# missing. The previous script then defaulted to "master", which labeled every
# scaled-out replica as master (apecloud/apecloud#21787). A non-zero exit keeps
# the previous role label instead of publishing a wrong one.

conf="${DATA_DIR:-/home/rocketmq/store}/broker.conf"
if [ ! -f "$conf" ]; then
    echo "broker.conf not found: $conf" >&2
    exit 1
fi

role=$(grep -E '^brokerRole=' "$conf" | tail -n 1 | cut -d= -f2 | tr -d '[:space:]')
case "$role" in
    SLAVE)
        echo -n "slave"
        ;;
    ASYNC_MASTER|SYNC_MASTER)
        echo -n "master"
        ;;
    *)
        echo "unknown brokerRole: ${role:-<empty>}" >&2
        exit 1
        ;;
esac
