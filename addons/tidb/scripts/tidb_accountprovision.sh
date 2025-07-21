#!/bin/sh

set -ex

eval statement=\"${KB_ACCOUNT_STATEMENT}\"
mysql -h"$TIDB_HOST" -P"$TIDB_PORT" -u root -p"$TIDB_ROOT_PASSWORD" -e "${statement}"
