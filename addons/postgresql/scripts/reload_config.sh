#!/bin/sh
set -e

if [ -t 0 ]; then
    # No stdin content (terminal is connected)
    echo "no stdin content"
    exit 0
fi

config_content=$(jq -c .)  # read from STDIN
echo "config content: <CONFIG>${config_content}</CONFIG>"

# Patch the config to apply the new config in Patroni
curl -X PATCH -d "${config_content}" localhost:8008/config

# Reload the new config in Patroni
curl -X POST -d '{ "timeout": 180 }' localhost:8008/reload

# Sleep for a while to make the new config take effect
sleep 10

# Get whether the master is pending for restart after applying the new config
pending_restart=$(curl localhost:8008 | jq .pending_restart)
echo "Master pending restart: '${pending_restart}'"

if [ "$pending_restart" != "true" ]; then
    echo "No need to restart the master after applying the new config"
    exit 0
fi

# begin to do restart
# restart the master first
echo "Restarting the master"
curl -X POST -d '{ "timeout": 180 }' localhost:8008/restart

# It is possible that some standbys has already been auto-started due to the key configuration check failed after master restarted
# So sleep for a while and check
sleep 10
curl localhost:8008/cluster | jq -r '.members[] | select(.role != "leader") | .host' | while read -r client_ip; do
    (
        echo "client ip: $client_ip"
        pending_restart=$(curl "$client_ip:8008" | jq .pending_restart)
        echo "standby '$client_ip': pending restart: '${pending_restart}'"
        if [ "${pending_restart}" = "true" ]; then
            curl -X POST -d '{ "restart_pending": true, "timeout": 180 }' "$client_ip:8008/restart"
        fi
    ) &
done

# wait all the standby restarted
wait
