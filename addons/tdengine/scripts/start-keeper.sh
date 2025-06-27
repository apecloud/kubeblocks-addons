while true; do
    es=$(taos -h 127.0.0.1 -P $TAOS_SERVICE_PORT --check | grep "^[0-9]*:")
    echo ${es}
    if [ "${es%%:*}" -eq 2 ]; then
        echo "$(date) INFO: TDengine is ready, starting taoskeeper..."
        break
    fi
    echo "$(date) INFO: TDengine is not ready, waiting..."
    sleep 1s
done

override_config="/var/lib/taoskeeper.toml"
cp /etc/taos/taoskeeper.toml $override_config


instanceId=${CURRENT_POD_NAME##*-}
sed -i "s|^password = .*|password = \"${TAOS_ROOT_PASSWORD}\"|g" $override_config
sed -i "s|^instanceId = .*|instanceId = ${instanceId}|g" $override_config

exec taoskeeper -c $override_config