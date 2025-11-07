#!/bin/bash
set -e

# hack for rocketmq 4.9.6
cd /home/rocketmq/rocketmq-4.9.6/bin

MAX_RETRIES=3
RETRY_INTERVAL=5
retries=0
broker_addrs=""
namesrv_addrs=${ALL_NAMESRV_FQDN//,/:${LISTEN_PORT};}:${LISTEN_PORT}
while [[ $retries -lt $MAX_RETRIES ]]; do
    for addr in $namesrv_addrs; do
        if [[ -z $broker_addrs ]]; then
           if output=$(./mqadmin clusterList -n "$addr" 2>/dev/null); then
               broker_addrs=$(echo "$output" | awk 'NR>1 {print $4}')
           fi
        fi
    done

    if [[ -n $broker_addrs ]]; then
        break
    fi
    sleep $RETRY_INTERVAL
    ((retries++))
done

if [[ -z $broker_addrs ]]; then
    echo "Error: Failed to obtain Broker address (NameServer may not be started)."
    exit 1
else
    echo "Broker address obtained successfully: $broker_addrs"
fi

all_nameserver_addrs=""
for addr in $namesrv_addrs; do
    # compatible with member join and member leave
    if [[ -n $KB_LEAVE_MEMBER_POD_NAME && "$addr" == *"$KB_LEAVE_MEMBER_POD_NAME"* ]]; then
        continue
    fi

    if [[ -z $all_nameserver_addrs ]]; then
        all_nameserver_addrs="$addr"
    else
        all_nameserver_addrs="$all_nameserver_addrs;$addr"
    fi
done


echo "Updating Broker configuration with NameServer addresses: $all_nameserver_addrs"
for addr in ${broker_addrs}; do
    ./mqadmin updateBrokerConfig -b "$addr" -k "namesrvAddr" -v "$all_nameserver_addrs"
done

