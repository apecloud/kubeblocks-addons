#!/bin/bash

export NAMESRV_ADDR=${ALL_NAMESRV_FQDN//,/:${NAMESRV_PORT};}:${NAMESRV_PORT}
export PATH="$PATH:/opt/java/openjdk/bin"

# 1. stop broker write
/home/rocketmq/rocketmq-"${ROCKETMQ_VERSION}"/bin/mqadmin updateBrokerConfig -b "${MY_POD_IP}:${BROKER_PORT}" -k brokerPermission -v 4

# 2. checking consume stats
max_retries=3
diff_left=true
for ((i=1; i<=max_retries; i++)); do
    stats=$(/home/rocketmq/rocketmq-"${ROCKETMQ_VERSION}"/bin/mqadmin brokerConsumeStats -b "${MY_POD_IP}:${BROKER_PORT}")
    diff_total=$(echo "$stats" | grep "Diff Total" | awk -F': ' '{print $2}')
    if [ "$diff_total" -eq 0 ]; then
        echo "All messages have been consumed. Proceeding to remove the broker."
        diff_left=false
    else
        echo "There are still unconsumed messages (Diff Total: $diff_total). Checking again in 1 seconds... ($i/$max_retries)"
        sleep 1
    fi
done

if [ "$diff_left" = true ]; then
    echo "Error: There are still unconsumed messages after $max_retries checks. Aborting broker removal."
    exit 1
fi
