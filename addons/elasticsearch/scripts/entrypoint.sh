#!/usr/bin/env sh
if [ "${TLS_ENABLED}" = "true" ]; then
  cp /etc/pki/tls/* /usr/share/elasticsearch/config/
fi
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

TMP_NODE_EXTRA_CONFIG=$(mktemp /tmp/es-node-extra-config.XXXXXX)
: > "${TMP_NODE_EXTRA_CONFIG}"

if [ -n "${REMOTE_PRIMARY_HOST}" ] && [ -n "${REMOTE_PRIMARY_PORT}" ] && [ -n "${ELASTICSEARCH_REPLAY_START_TIME_MS}" ]; then
  {
    printf '  source_extract_start_time: %s\n' "${ELASTICSEARCH_REPLAY_START_TIME_MS}"
    printf '  source_extract_idx_host: "%s:%s"\n' "${REMOTE_PRIMARY_HOST}" "${REMOTE_PRIMARY_PORT}"
    printf '  source_extract_idx_user: "%s"\n' "${REMOTE_PRIMARY_USER:-}"
    printf '  source_extract_idx_password: "%s"\n' "${REMOTE_PRIMARY_PASSWORD:-}"
    if [ "${ELASTICSEARCH_REPLAY_IS_START_AFTER_RUNNING}" = "true" ]; then
      printf '  source_extract_enabled: true\n'
    fi
  } >> "${TMP_NODE_EXTRA_CONFIG}"
fi

if [ -d /usr/share/elasticsearch/plugins ] && [ -n "$(find /usr/share/elasticsearch/plugins -mindepth 1 -maxdepth 1 -type d -name 'es-extract-*' -print -quit)" ]; then
  {
    printf '  extract_idx_host: "%s:%s"\n' "${ELASTICSEARCH_HOST}" "${ELASTICSEARCH_PORT:-9200}"
    printf '  extract_idx_user: "%s"\n' "${ELASTIC_USERNAME:-elastic}"
    printf '  extract_idx_password: "%s"\n' "${ELASTIC_PASSWORD:-}"
  } >> "${TMP_NODE_EXTRA_CONFIG}"
fi

if [ -s "${TMP_NODE_EXTRA_CONFIG}" ]; then
  TMP_NODE_EXTRA_SED_SCRIPT=$(mktemp /tmp/es-node-extra-sed.XXXXXX)
  {
    printf '/^  #__CUSTOM_PLUGIN_EXTRA_CONFIGS__$/c\\\n'
    sed 's/[\\&]/\\&/g; s/$/\\/' "${TMP_NODE_EXTRA_CONFIG}"
  } > "${TMP_NODE_EXTRA_SED_SCRIPT}"
  sed -i -f "${TMP_NODE_EXTRA_SED_SCRIPT}" config/elasticsearch.yml
  rm -f "${TMP_NODE_EXTRA_SED_SCRIPT}"
else
  sed -i '/^  #__CUSTOM_PLUGIN_EXTRA_CONFIGS__$/d' config/elasticsearch.yml
fi

rm -f "${TMP_NODE_EXTRA_CONFIG}"

if [ -f /bin/tini ]; then
  /bin/tini -- /usr/local/bin/docker-entrypoint.sh
elif [ -f /tini ]; then
  /tini -- /usr/local/bin/docker-entrypoint.sh
else
  /usr/local/bin/docker-entrypoint.sh
fi
