#!/bin/bash

# Set for `JAVA_OPT`.
JAVA_OPTS="${JAVA_OPTS} -Drocketmq.config.namesrvAddrs=${NAMESRV_HOST}:${NAMESRV_PORT}"

if [ "$ENABLE_ACL" = "true" ]; then
    echo "Initializing rocketmq-dashboard acl configuration"

    JAVA_OPTS="${JAVA_OPTS} -Drocketmq.config.loginRequired=true"
    JAVA_OPTS="${JAVA_OPTS} -Drocketmq.config.dataPath=${CONFIG_PATH}"

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

    JAVA_OPTS="${JAVA_OPTS} -Drocketmq.config.accessKey=${ak}"
    JAVA_OPTS="${JAVA_OPTS} -Drocketmq.config.secretKey=${sk}"

    if [ ! -f "$CONFIG_PATH"/users.properties ]; then
        echo "${CONSOLE_USER}=${CONSOLE_PASSWORD},1" >> "$CONFIG_PATH"/users.properties
    fi
fi

sh -c "java $JAVA_OPTS -jar /rocketmq-dashboard.jar"