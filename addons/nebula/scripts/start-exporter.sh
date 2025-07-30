#!/bin/sh

cat <<EOF > /config.yaml
clusters:
  - name: ${CLUSTER_NAME}
    instances:
      - name: ${COMPONENT_TYPE}
        endpointIP: ${POD_FQDN}
        endpointPort: ${HTTP_PORT}
        componentType: ${COMPONENT_TYPE}
EOF
exec /nebula-stats-exporter --bare-metal --bare-metal-config=/config.yaml