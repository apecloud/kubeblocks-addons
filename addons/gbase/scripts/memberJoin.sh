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
IP_LIST_COMMA=$(IFS=,; echo "${IP_LIST[*]}")
HOSTNAME_LIST_COMMA=$(IFS=,; echo "${HOSTNAME_LIST[*]}")
echo $IP_LIST_COMMA
echo $HOSTNAME_LIST_COMMA

# find join_pod_ip in cluster
if [[ " ${IP_LIST[@]} " =~ " ${JOIN_POD_IP} " ]]; then
  exit 0
else
  # config hostname trust (gbase needed)
  echo "$JOIN_POD_IP $JOIN_POD_NAME" | sudo tee -a /etc/hosts

  # join new node ip and host
  IP_LIST_COMMA="$IP_LIST_COMMA,$JOIN_POD_IP"
  HOSTNAME_LIST_COMMA="$HOSTNAME_LIST_COMMA,$JOIN_POD_NAME"

  echo "${HOSTNAME_LIST_COMMA[@]}"
  echo "${IP_LIST_COMMA[@]}"

  # generate new cluster xml
  python3 /scripts/generate_replica_xml.py "${HOSTNAME_LIST_COMMA[@]}" "${IP_LIST_COMMA[@]}"
  
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
