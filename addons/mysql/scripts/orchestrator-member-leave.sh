#!/bin/sh
set -ex

cluster_component_pod_name="$KB_CLUSTER_COMP_NAME"
component_name="$KB_COMP_NAME"
last_digit=${KB_LEAVE_MEMBER_POD_NAME##*-}
self_service_name=$(echo "${cluster_component_pod_name}_${component_name}_${last_digit}" | tr '_' '-' | tr '[:upper:]' '[:lower:]' )

# register first pod to orchestrator
forget_from_orchestrator() {
  local host_ip=$1

  # send request to orchestrator for discovery
  /scripts/orchestrator-client -c forget -i ${host_ip}:3306
}

main() {
  last_digit=${KB_LEAVE_MEMBER_POD_NAME##*-}
  self_service_name=$(echo "${cluster_component_pod_name}_${component_name}_${last_digit}" | tr '_' '-' | tr '[:upper:]' '[:lower:]' )
  forget_from_orchestrator "$self_service_name"
}
