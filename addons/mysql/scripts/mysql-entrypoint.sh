#!/bin/bash
REPORT_HOST=${POD_NAME}.${CLUSTER_NAMESPACE}
SERVICE_ID=$((${POD_NAME##*-} + 1))
if [ "${MYSQL_MAJOR}" = '5.7' ]; then
  /scripts/docker-entrypoint.sh mysqld --server-id $SERVICE_ID --report-host ${REPORT_HOST} \
    --ignore-db-dir=lost+found \
    --plugin-load-add=rpl_semi_sync_master=semisync_master.so \
    --plugin-load-add=rpl_semi_sync_slave=semisync_slave.so \
    --plugin-load-add=audit_log=audit_log.so \
    --log-bin=/var/lib/mysql/binlog/${POD_NAME}-bin \
    --skip-slave-start=$skip_slave_start
elif [ "${MYSQL_MAJOR}" = '8.0' ]; then
  docker-entrypoint.sh mysqld --server-id $SERVICE_ID --report-host ${REPORT_HOST} \
    --plugin-load-add=rpl_semi_sync_source=semisync_source.so \
    --plugin-load-add=rpl_semi_sync_replica=semisync_replica.so \
    --plugin-load-add=audit_log=audit_log.so \
    --log-bin=/var/lib/mysql/binlog/${POD_NAME}-bin \
    --skip-slave-start=$skip_slave_start
else
  echo "Unsupported MySQL version"
  exit 1
fi