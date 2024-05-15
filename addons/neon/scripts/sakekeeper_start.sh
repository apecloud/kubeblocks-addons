#!/bin/bash
set -ex

# Handle termination gracefully
trap : TERM INT

# Generate the NEON_BROKER_SVC endpoint from the list of pod names
IFS=',' read -ra BROKER_ARRAY <<< "$NEON_STORAGEBROKER_POD_LIST"
BROKER_SVC=""
for pod in "${BROKER_ARRAY[@]}"; do
    BROKER_SVC+="${pod}.${NEON_STORAGEBROKER_HEADLESS}.default.svc.cluster.local,"
done
BROKER_SVC="${BROKER_SVC%,}"

# Start safekeeper with the dynamically generated broker endpoint
exec safekeeper --id=1 -D /data --broker-endpoint=http://$BROKER_SVC:50051 -l ${POD_IP}:5454 --listen-http=0.0.0.0:7676