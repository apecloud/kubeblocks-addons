#!/bin/bash

set -exo pipefail

# shellcheck disable=SC1091
. /scripts/common.sh

echo "start tikv..."

exec /tikv-server --pd="http://${PD_ADDRESS}" \
    --data-dir=/var/lib/tikv \
    --addr=0.0.0.0:20160 \
    --advertise-addr="${CURRENT_POD_NAME}.${TIKV_COMPONENT_NAME}-headless.${DOMAIN}:20160" \
    --status-addr=0.0.0.0:20180 \
    --config=/etc/tikv/tikv.toml