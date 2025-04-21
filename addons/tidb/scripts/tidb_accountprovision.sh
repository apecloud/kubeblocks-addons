#!/bin/sh

set -ex

eval statement=\"${KB_ACCOUNT_STATEMENT}\"
mysql -h127.0.0.1 -P"$TIDB_PORT" -u root -p"$TIDB_ROOT_PASSWORD" -e "${statement}"
