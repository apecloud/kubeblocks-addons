#!/bin/bash

set -ex

# Handle termination gracefully
trap : TERM INT

# Start safekeeper with the dynamically generated broker endpoint
exec safekeeper --id=1 -D /data --broker-endpoint=http://$NEON_STORAGEBROKER_POD_FQDN_LIST:$NEON_STORAGEBROKER_PORT -l ${POD_IP}:$SAFEKEEPER_PG_PORT --listen-http=0.0.0.0:$SAFEKEEPER_HTTP_PORT