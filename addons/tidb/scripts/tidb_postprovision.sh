#!/bin/sh

set -ex

mysql -h"$TIDB_HOST" -P"$TIDB_PORT" -u root -e "set password for 'root'@'%' = '$TIDB_ROOT_PASSWORD'"
