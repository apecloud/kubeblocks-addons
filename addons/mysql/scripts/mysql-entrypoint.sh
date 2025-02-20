#!/bin/bash
self_last_digit=${POD_NAME##*-}
fqdn_name=${CLUSTER_COMPONENT_NAME}-${self_last_digit}.${CLUSTER_COMPONENT_NAME}-headless
if [ ${#fqdn_name} -gt 60 ] && [ "${MYSQL_MAJOR}" = "5.7" ]; then
    echo "Error: The length of the variable exceeds 60 characters"
    exit 1
fi
SERVICE_ID=$((${POD_NAME##*-} + 1))
if [ "${MYSQL_MAJOR}" = '5.7' ]; then
  /scripts/docker-entrypoint.sh mysqld --server-id $SERVICE_ID --report-host ${fqdn_name} \
    --ignore-db-dir=lost+found \
    --plugin-load-add=rpl_semi_sync_master=semisync_master.so \
    --plugin-load-add=rpl_semi_sync_slave=semisync_slave.so \
    --plugin-load-add=audit_log=audit_log.so \
    --log-bin=/var/lib/mysql/binlog/${POD_NAME}-bin \
    --skip-slave-start=$skip_slave_start
elif [ "${MYSQL_MAJOR}" = '8.0' ]; then
  docker-entrypoint.sh mysqld --server-id $SERVICE_ID --report-host ${fqdn_name} \
    --plugin-load-add=rpl_semi_sync_source=semisync_source.so \
    --plugin-load-add=rpl_semi_sync_replica=semisync_replica.so \
    --plugin-load-add=audit_log=audit_log.so \
    --log-bin=/var/lib/mysql/binlog/${POD_NAME}-bin \
    --skip-slave-start=$skip_slave_start
else
  echo "Unsupported MySQL version"
  exit 1
fi