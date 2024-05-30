#!/bin/bash
REPORT_HOST=MYSQL_ORDINAL_HOST_${KB_POD_NAME##*-}
if [ "${MYSQL_MAJOR}" = '5.7' ]; then
  /scripts/docker-entrypoint-5.7.sh mysqld --server-id $(( ${KB_POD_NAME##*-} + 1)) \
    --ignore-db-dir=lost+found \
    --plugin-load-add=rpl_semi_sync_master=semisync_master.so \
    --plugin-load-add=rpl_semi_sync_slave=semisync_slave.so \
    --plugin-load-add=audit_log=audit_log.so \
    --log-bin={{.Values.dataMountPath}}/binlog/$(KB_POD_NAME)-bin \
    --skip-slave-start=$skip_slave_start
else
docker-entrypoint.sh mysqld --server-id $(( ${KB_POD_NAME##*-} + 1)) \
   --ignore-db-dir=lost+found \
   --plugin-load-add=rpl_semi_sync_master=semisync_master.so \
   --plugin-load-add=rpl_semi_sync_slave=semisync_slave.so \
   --plugin-load-add=audit_log=audit_log.so \
   --log-bin={{.Values.dataMountPath}}/binlog/$(KB_POD_NAME)-bin \
   --skip-slave-start=$skip_slave_start
fi