#!/bin/bash

set -e

replicas=$(echo "${POD_FQDN_LIST}" | tr ',' '\n')
for replica in $replicas; do
    # it seems like repetitively adding data nodes has no side effect
    influxd-ctl -bind "$META_ADDRESS" add-data "$replica:8088"
done

# the image has a init-influxdb.sh that does admin user creation,
# but it only reties 30 seconds and errors out. It may not be enough time for
# the post-provisioning script to succuess. So we manually do the creation here.
init_query="CREATE USER \"$INFLUXDB_ADMIN_USER_POSTPROVISON\" WITH PASSWORD '$INFLUXDB_ADMIN_PASSWORD' WITH ALL PRIVILEGES"
cmd="/tools/influx -host 127.0.0.1 -port 8086 -execute "
$cmd "$init_query"
echo "admin user \"$INFLUXDB_ADMIN_USER_POSTPROVISON\" created"
