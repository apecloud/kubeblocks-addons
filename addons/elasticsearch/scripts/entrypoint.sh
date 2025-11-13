#!/usr/bin/env sh
cp /etc/pki/tls/* /usr/share/elasticsearch/config/
# Parse zone from ZONE_AWARE_MAPPING based on NODE_NAME
if [ "${ZONE_AWARE_ENABLED}" = "true" ]; then
  if [ -z "${ZONE_AWARE_MAPPING}" ]; then
    echo "Error: ZONE_AWARE_ENABLED is true but ZONE_AWARE_MAPPING is not set"
    exit 1
  fi
  if [ -z "${NODE_NAME}" ]; then
    echo "Error: ZONE_AWARE_ENABLED is true but NODE_NAME is not set"
    exit 1
  fi
  ZONE_NAME=""
  IFS=';' read -ra PARTS <<< "${ZONE_AWARE_MAPPING}"
  for PART in "${PARTS[@]}"; do
    IFS=':' read -ra ZONE_PART <<< "${PART}"
    if [ ${#ZONE_PART[@]} -eq 2 ]; then
      ZONE="${ZONE_PART[0]// /}"
      NODES="${ZONE_PART[1]}"
      IFS=',' read -ra NODE_LIST <<< "${NODES}"
      for NODE in "${NODE_LIST[@]}"; do
        NODE_NAME_TRIMMED="${NODE// /}"
        if [ "${NODE_NAME_TRIMMED}" = "${NODE_NAME}" ]; then
          export ZONE_NAME="${ZONE}"
          break
        fi
      done
      if [ -n "${ZONE_NAME}" ]; then
        break
      fi
    fi
  done
  if [ -z "${ZONE_NAME}" ]; then
    echo "Error: ZONE_AWARE_ENABLED is true but failed to find zone for node ${NODE_NAME} in ZONE_AWARE_MAPPING: ${ZONE_AWARE_MAPPING}"
    exit 1
  fi
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