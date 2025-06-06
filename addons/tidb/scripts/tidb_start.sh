#!/bin/bash

set -exo pipefail

# shellcheck disable=SC1091
. /scripts/common.sh

echo "start tidb..."
write_component_tls_env_to_file

exec /tidb-server --store=tikv \
    --advertise-address="${CURRENT_POD_NAME}.${TIDB_COMPONENT_NAME}-headless.${DOMAIN}" \
    --host=0.0.0.0 \
    --path="${PD_ADDRESS}" \
    --log-slow-query=/var/log/tidb/slowlog \
    --log-file=/var/log/tidb/running.log \
    --config=/etc/tidb/tidb.toml
