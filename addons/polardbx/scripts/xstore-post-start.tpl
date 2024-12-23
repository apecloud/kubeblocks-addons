#!/bin/sh

# setup shared-channel.json
SHARED_CHANNEL_JSON='{"nodes": ['

# Convert comma-separated list of FQDNs to array
IFS=',' read -r -a pod_fqdns <<< "$POD_FQDN_LIST"

for hostname in "${pod_fqdns[@]}"; do
  # Extract pod name from FQDN (first segment before the dot)
  pod=$(echo "$hostname" | cut -d'.' -f1)

  NODE_OBJECT=$(printf '{"pod": "%s", "host": "%s", "port": 11306, "role": "candidate", "node_name": "%s" }' "$pod" "$hostname" "$pod")
  SHARED_CHANNEL_JSON+="$NODE_OBJECT,"
done

SHARED_CHANNEL_JSON=${SHARED_CHANNEL_JSON%,}
SHARED_CHANNEL_JSON+=']}'

mkdir -p /data/shared/
echo $SHARED_CHANNEL_JSON > /data/shared/shared-channel.json