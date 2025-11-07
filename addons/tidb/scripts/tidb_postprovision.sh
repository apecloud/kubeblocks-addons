#!/bin/sh

set -ex

if mysql -h127.0.0.1 -P"$TIDB_PORT" -u root -p"$TIDB_ROOT_PASSWORD" -e 'select 1'; then
    exit 0
fi

mysql -h127.0.0.1 -P"$TIDB_PORT" -u root -e "set password for 'root'@'%' = '$TIDB_ROOT_PASSWORD'"
