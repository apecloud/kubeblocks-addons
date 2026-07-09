#!/bin/bash
set -e
set -o pipefail

wait_for_mongos_router_ready

echo "INFO: Post-restore mongos router is ready."
