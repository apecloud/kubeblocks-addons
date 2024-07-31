#!/bin/bash   

JOIN_POD_NAME=$1
JOIN_POD_IP=$2
HOSTNAME_LIST=()
IP_LIST=()

if [[ -z "$JOIN_POD_NAME" || -z "$JOIN_POD_IP" ]]; then
  echo "Error: JOIN_POD_NAME and JOIN_POD_IP must be set."
  exit 1
fi

# get cluster running node ip and hostname
output=$(sudo -i -u gbase gs_om -t status --all)
if [[ $? -ne 0 ]]; then
  echo "Failed to execute 'gs_om -t status --all'"
  exit 1
fi
while IFS= read -r line; do
  if [[ "$line" =~ node_name[[:space:]]*:[[:space:]]*(.*) ]]; then
    HOSTNAME_LIST+=("${BASH_REMATCH[1]}")
  elif [[ "$line" =~ node_ip[[:space:]]*:[[:space:]]*(.*) ]]; then
    IP_LIST+=("${BASH_REMATCH[1]}")
  fi
done <<< "$output"

echo "IP_LIST: ${IP_LIST[@]}"
echo "HOSTNAME_LIST: ${HOSTNAME_LIST[@]}"

# find join_pod_ip in cluster
if [[ " ${IP_LIST[@]} " =~ " ${JOIN_POD_IP} " ]]; then
  exit 0
else
  # config hostname trust (gbase needed)
  IP_LIST+=("$JOIN_POD_IP")
  HOSTNAME_LIST+=("$JOIN_POD_NAME")

  # Generate comma-separated lists for the XML generation
  IP_LIST_COMMA=$(IFS=','; echo "${IP_LIST[*]}")
  HOSTNAME_LIST_COMMA=$(IFS=','; echo "${HOSTNAME_LIST[*]}")

  TEMP_FILE=$(mktemp)
  cp /etc/hosts "$TEMP_FILE"

  for index in "${!IP_LIST[@]}"; do
    NODE_IP="${IP_LIST[$index]}"
    NODE_NAME="${HOSTNAME_LIST[$index]}"
    
    # Check if the IP already exists in /etc/hosts
    if grep -q "^$NODE_IP\b" "$TEMP_FILE"; then
      # Check if the hostname is already associated with the IP
      if grep -q "^$NODE_IP\b.*\b$NODE_NAME\b" "$TEMP_FILE"; then
        echo "IP $NODE_IP with hostname $NODE_NAME already exists, skipping..."
        continue
      else
        # If the hostname does not exist, replace the entire line
        sed -i "/^$NODE_IP\b/c\\$NODE_IP $NODE_NAME" "$TEMP_FILE"
        echo "Replaced entry for IP $NODE_IP with hostname $NODE_NAME"
      fi
    else
      # If the hostname exists
      if grep -q "[[:space:]]$NODE_NAME\b" "$TEMP_FILE"; then
        sed -i "/[[:space:]]$NODE_NAME\b/c\\$NODE_IP $NODE_NAME" "$TEMP_FILE"
        echo "Updated entry for hostname $NODE_NAME with IP $NODE_IP"
      else
        # If neither the IP nor the hostname exists, add a new entry
        echo "$NODE_IP $NODE_NAME" | tee -a "$TEMP_FILE" > /dev/null
        echo "Adding new entry for $NODE_IP $NODE_NAME"
      fi
    fi
  done

  # Replace /etc/hosts with the modified temporary file
  sudo cp "$TEMP_FILE" /etc/hosts
  sudo rm "$TEMP_FILE"

  # generate new cluster xml
  python3 /scripts/generate_HA_cluster_xml.py "$HOSTNAME_LIST_COMMA" "$IP_LIST_COMMA"
  /home/gbase/gbase_package/script/gs_expansion -U gbase -G gbase -X /home/gbase/cluster.xml -h $JOIN_POD_IP

  # check expansion success or fail
  output=$(sudo -i -u gbase gs_om -t status -h $JOIN_POD_NAME)  
  if echo "$output" | grep -q 'instance_state\s*:\s*Normal'; then
    echo "gs_expansion success"
  else
    echo "gs_expansion failed"
    exit 1
  fi

fi
