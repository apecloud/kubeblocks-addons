#!/bin/bash

set -ex

# Handle termination gracefully
trap : TERM INT

# Start safekeeper with the dynamically generated broker endpoint
exec pageserver -D /data -c "id=1" -c "broker_endpoint='http://$NEON_STORAGEBROKER_POD_FQDN_LIST:$NEON_STORAGEBROKER_PORT'" -c "listen_pg_addr='0.0.0.0:$PAGEKEEPER_PG_PORT'" -c "listen_http_addr='0.0.0.0:$PAGEKEEPER_HTTP_PORT'" -c "pg_distrib_dir='/opt/neondatabase-neon/pg_install'"
