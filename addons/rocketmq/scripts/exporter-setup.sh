#!/bin/bash

namesrvAddr="${NAMESRV_HOST}:${NAMESRV_PORT}"
version=${ROCKETMQ_VERSION:-4.9.6}
new_version=$(echo "$version" | sed 's/^/V/' | tr '.' '_')

echo "Starting connection check for ${namesrvAddr}"
retry_count=0
max_retries=60
while [ $retry_count -lt $max_retries ]; do
    curl -s --connect-timeout 1 "${namesrvAddr}" >/dev/null
    # curl: (52) Empty reply from server
    if [ $? -eq 52 ]; then
        echo "Successfully connected to ${namesrvAddr}"
        break
    fi

    retry_count=$((retry_count + 1))
    echo "Attempt $retry_count of $max_retries failed, retrying in 1 seconds..."
    sleep 1
done

if [ "$ENABLE_ACL" = "true" ]; then
    ak=""
    for env_var in $(env | grep -E '^ROCKETMQ_USER'); do
        value="${env_var#*=}"
        if [ -n "$value" ]; then
            if [ -n "$last_value" ] && [ "$last_value" != "$value" ]; then
                echo "Error conflicting env $env_var of rocketmq-broker default user values found, all the components' default user of rocketmq-broker must be the same."
                exit 1
            fi
            last_value="$value"
        fi
    done
	  ak="$last_value"

    sk=""
    last_value=""
    for env_var in $(env | grep -E '^ROCKETMQ_PASSWORD'); do
        value="${env_var#*=}"
        if [ -n "$value" ]; then
            if [ -n "$last_value" ] && [ "$last_value" != "$value" ]; then
                echo "Error conflicting env $env_var of rocketmq-broker password values found, all the components' password of rocketmq-broker must be the same."
                exit 1
            fi
            last_value="$value"
        fi
    done
	  sk="$last_value"

    java -jar rocketmq-exporter.jar \
        --rocketmq.config.namesrvAddr="${namesrvAddr}" \
        --rocketmq.config.rocketmqVersion="${new_version}" \
        --rocketmq.config.enableACL=true \
        --rocketmq.config.accessKey="${ak}" \
        --rocketmq.config.secretKey="${sk}"
else
    java -jar rocketmq-exporter.jar \
        --rocketmq.config.namesrvAddr="${namesrvAddr}" \
        --rocketmq.config.rocketmqVersion="${new_version}"
fi