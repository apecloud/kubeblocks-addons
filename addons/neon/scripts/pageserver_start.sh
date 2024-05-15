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
exec pageserver -D /data -c "id=1" -c "broker_endpoint='http://$BROKER_SVC:50051'" -c "listen_pg_addr='0.0.0.0:6400'" -c "listen_http_addr='0.0.0.0:9898'" -c "pg_distrib_dir='/opt/neondatabase-neon/pg_install'"
