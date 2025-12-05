#!/usr/bin/env sh
cp /etc/pki/tls/* /usr/share/elasticsearch/config/
# Parse zone from zone-aware-mapping file based on NODE_NAME
# Zone-aware-mapping file format: YAML format with zone name as key and comma-separated node names as value
# Empty node list is allowed for a zone
# Example:
#   zone1: node1,node2
#   zone2: node3,node4,node5
#   zone3:
ZONE_AWARE_MAPPING_FILE="/mnt/zone-aware-mapping/mapping"
if [ "${ZONE_AWARE_ENABLED}" = "true" ]; then
  if [ ! -f "${ZONE_AWARE_MAPPING_FILE}" ]; then
    echo "Error: ZONE_AWARE_ENABLED is true but zone-aware-mapping file not found at ${ZONE_AWARE_MAPPING_FILE}"
    exit 1
  fi
  if [ -z "${NODE_NAME}" ]; then
    echo "Error: ZONE_AWARE_ENABLED is true but NODE_NAME is not set"
    exit 1
  fi
  CURRENT_ZONE=""
  ZONES=()
  # Parse YAML format: each line is "zone_name: node1,node2,..."
  while IFS= read -r LINE || [ -n "${LINE}" ]; do
    # Skip empty lines and comments
    LINE="${LINE%%#*}"  # Remove comments
    LINE=$(echo "${LINE}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')  # Trim whitespace
    if [ -z "${LINE}" ]; then
      continue
    fi
    # Split by first colon to get zone name and node list
    ZONE_NAME="${LINE%%:*}"
    NODE_LIST="${LINE#*:}"
    # Trim whitespace
    ZONE_NAME=$(echo "${ZONE_NAME}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    NODE_LIST=$(echo "${NODE_LIST}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # Skip if zone name is empty (node list can be empty)
    if [ -z "${ZONE_NAME}" ]; then
      continue
    fi
    # Add zone to ZONES array (even if node list is empty)
    ZONES+=("${ZONE_NAME}")
    # Check if current node is in this zone (only if not found yet and node list is not empty)
    if [ -z "${CURRENT_ZONE}" ] && [ -n "${NODE_LIST}" ]; then
      IFS=',' read -ra NODES <<< "${NODE_LIST}"
      for NODE in "${NODES[@]}"; do
        NODE_TRIMMED=$(echo "${NODE}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -n "${NODE_TRIMMED}" ] && [ "${NODE_TRIMMED}" = "${NODE_NAME}" ]; then
          export CURRENT_ZONE="${ZONE_NAME}"
          break
        fi
      done
    fi
  done < "${ZONE_AWARE_MAPPING_FILE}"
  if [ -z "${CURRENT_ZONE}" ]; then
    echo "Error: ZONE_AWARE_ENABLED is true but failed to find zone for node ${NODE_NAME} in zone-aware-mapping file"
    exit 1
  fi
  echo "CURRENT_ZONE: ${CURRENT_ZONE}"
  # Check if ZONES is empty
  if [ ${#ZONES[@]} -eq 0 ]; then
    echo "Error: ZONE_AWARE_ENABLED is true but failed to find zones in zone-aware-mapping file"
    exit 1
  fi
  export ALL_ZONES=$(IFS=,; echo "${ZONES[*]}")
  echo "ALL_ZONES: ${ALL_ZONES}"
fi

# remove initial master nodes block if cluster has been formed
if [ -f "${CLUSTER_FORMED_FILE}" ]; then
  sed -i '/# INITIAL_MASTER_NODES_BLOCK_START/,/# INITIAL_MASTER_NODES_BLOCK_END/d' config/elasticsearch.yml
fi
if [ -f /bin/tini ]; then
  /bin/tini -- /usr/local/bin/docker-entrypoint.sh
elif [ -f /tini ]; then
  /tini -- /usr/local/bin/docker-entrypoint.sh
else
  /usr/local/bin/docker-entrypoint.sh
fi