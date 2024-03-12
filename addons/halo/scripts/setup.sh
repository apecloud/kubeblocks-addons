#!/bin/bash
set -o errexit
set -o nounset

# /halo-scripts/halo-entrypoint.sh postgres

chown -R halo:halo /data/halo
chmod 0750 /data/halo

cat > /etc/patroni/patroni.yml << __EOF__
restapi:
  connect_address: '${PATRONI_KUBERNETES_POD_IP}:8008'

log:
  dateformat: '%Y-%m-%d %H:%M:%S'
  dir: /opt/patroni/logs
  file_size: 26214400
  level: INFO
  loggers:
    patroni.postmaster: WARNING
  traceback_level: ERROR


bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    master_start_timeout: 300
    maximum_lag_on_failover: 1048576
    synchronous_mode: false
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        wal_level: replica
        hot_standby: "on"
        max_wal_senders: 10
        max_replication_slots: 10
        wal_log_hints: "on"
postgresql:
  database: halo0root
  bin_dir: /u01/app/halo/product/dbms/14/bin
  connect_address: ${PATRONI_KUBERNETES_POD_IP}:1921
  data_dir: /data/halo
  pgpass: /opt/patroni/.pgpass
  custom_conf: /var/lib/halo/conf/postgresql.conf
  use_unix_socket: true
  parameters:
    unix_socket_directories: '/var/run/halo'
    standard_parserengine_auxiliary: "on"
    oracle.use_datetime_as_date: "true"
    transform_null_equals: "off"
  pg_hba:
  - local     all             all                                                   trust
  - local     replication     all                                                   trust
  - host      all             all                               0.0.0.0/0           md5
  - host      all             all                               ::/0                md5
  - host      replication     all                               0.0.0.0/0           md5
  - host      replication     all                               ::/0                md5

tags:
  clonefrom: false
  nofailover: false
  noloadbalance: false
  nosync: false
watchdog:
  mode: 'off'


__EOF__

gosu halo bash -c 'patroni /etc/patroni/patroni.yml' > /tmp/patroni.log 2>&1 &

#修改patroni配置参数
while ! pg_isready ; do 
    sleep 2
done

patronictl -c /etc/patroni/patroni.yml edit-config $PATRONI_SCOPE --pg database_compat_mode=oracle --pg max_connections=1000 --force 

sleep 1

patronictl -c /etc/patroni/patroni.yml restart  $PATRONI_SCOPE $PATRONI_NAME --pending --force 

wait



