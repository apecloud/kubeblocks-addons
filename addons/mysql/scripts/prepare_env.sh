#!/bin/bash
# This script prepares environment variables for Orchestrator client.
# It ensures ORCHESTRATOR_API is properly set using ORC_ENDPOINTS and ORC_PORTS.

# Prepares the ORCHESTRATOR_API environment variable if not already set.
# Constructs API URL from ORC_ENDPOINTS and ORC_PORTS, converting to lowercase
# and replacing underscores with hyphens.
prepare_orchestrator_env() {
   if [[ -z "$ORCHESTRATOR_API" ]]; then
     ORCHESTRATOR_API=$(echo "http://${ORC_ENDPOINTS%%:*}:${ORC_PORTS}" | tr '_' '-'  | tr '[:upper:]' '[:lower:]')
   fi
   export ORCHESTRATOR_API=$ORCHESTRATOR_API
}

# Check and prepare ORCHESTRATOR_API if not set
if [[ -z "$ORCHESTRATOR_API" ]]; then
  prepare_orchestrator_env
fi 