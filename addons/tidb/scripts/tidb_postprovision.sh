#!/bin/sh

set -ex

mysql -h127.0.0.1 -P"$TIDB_PORT" -u root -e "set password for 'root'@'%' = '$TIDB_ROOT_PASSWORD'"
