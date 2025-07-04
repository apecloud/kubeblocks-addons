#!/bin/bash
set -e
until curl -L -u root:${TAOS_ROOT_PASSWORD} localhost:${TAOS_ADAPTER_PORT}/rest/sql -d "show databases"; do sleep 1; done

override_config="/var/lib/taoskeeper.toml"
cp /etc/taos/taoskeeper.toml $override_config

instanceId=${CURRENT_POD_NAME##*-}
sed -i '/^password = /c\password = "'"$TAOS_ROOT_PASSWORD"'"' $override_config
sed -i "s|^instanceId = .*|instanceId = ${instanceId}|g" $override_config

exec taoskeeper -c $override_config