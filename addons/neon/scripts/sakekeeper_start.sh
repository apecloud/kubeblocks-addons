#!/bin/bash
set -ex

# Handle termination gracefully
trap : TERM INT

# Generate the NEON_BROKER_SVC endpoint from the list of pod names
IFS=',' read -ra BROKER_ARRAY <<< "$NEON_STORAGEBROKER_POD_LIST"
BROKER_SVC=""
for pod in "${BROKER_ARRAY[@]}"; do
    BROKER_SVC+="${pod}.${NEON_STORAGEBROKER_HEADLESS}.${KB_NAMESPACE}.svc.cluster.local,"
done
BROKER_SVC="${BROKER_SVC%,}"

# Start safekeeper with the dynamically generated broker endpoint
exec safekeeper --id=1 -D /data --broker-endpoint=http://$BROKER_SVC:$NEON_STORAGEBROKER_PORT -l ${POD_IP}:$SAFEKEEPER_PG_PORT --listen-http=0.0.0.0:$SAFEKEEPER_HTTP_PORT