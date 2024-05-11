#!/bin/bash

topology_info=$(/kubeblocks/orchestrator-client -c topology -i $KB_CLUSTER_NAME) || true
if [[ $topology_info == "" ]] || [[ $topology_info =~ ^ERROR ]]; then
  exit 0
fi

first_line=$(echo "$topology_info" | head -n 1)
cleaned_line=$(echo "$first_line" | tr -d '[]')
old_ifs="$IFS"
IFS=',' read -ra status_array <<< "$cleaned_line"
IFS="$old_ifs"
status="${status_array[1]}"
if  [ "$status" == "ok" ]; then
  exit 0
fi

address_port=$(echo "$first_line" | awk '{print $1}')
master_from_orc="${address_port%:*}"
last_digit=${KB_POD_NAME##*-}
self_service_name=$(echo "${KB_CLUSTER_COMP_NAME}_${KB_COMP_NAME}_${last_digit}" | tr '_' '-' | tr '[:upper:]' '[:lower:]' )
if [ "$master_from_orc" == "${self_service_name}" ]; then
  echo -n "primary"
else
  echo -n "secondary"
fi