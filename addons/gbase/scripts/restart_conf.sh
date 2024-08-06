#!/bin/bash

generate_tmp_ip() {
  echo "999.999.999.999.$1"
}

# read new ip and hostname
NEW_HOSTNAME_LIST=(${1//,/ })
NEW_IP_LIST=(${2//,/ })

# get old ip and hostname
output=$(sudo -i -u gbase gs_om -t status --all)
if [[ $? -ne 0 ]]; then
  echo "Failed to execute 'gs_om -t status --all'"
  exit 1
fi

declare -a OLD_HOSTNAME_LIST
declare -a OLD_IP_LIST

while IFS= read -r line; do
  if [[ "$line" =~ node_name[[:space:]]*:[[:space:]]*(.*) ]]; then
    OLD_HOSTNAME_LIST+=("${BASH_REMATCH[1]}")
  elif [[ "$line" =~ node_ip[[:space:]]*:[[:space:]]*(.*) ]]; then
    OLD_IP_LIST+=("${BASH_REMATCH[1]}")
  fi
done <<< "$output"

# 检查旧的和新的主机名是否相等
if [[ $(IFS=$'\n' ; echo "${OLD_HOSTNAME_LIST[*]}" | sort) != $(IFS=$'\n' ; echo "${NEW_HOSTNAME_LIST[*]}" | sort) ]]; then
  echo "Error: The old and new hostname lists do not contain the same elements."
  exit 1
fi

declare -a TEMP_IP_LIST=()
for index in "${!OLD_IP_LIST[@]}"; do
  TEMP_IP_LIST+=("$(generate_tmp_ip $index)")
done

# 首先将旧 IP 替换为临时 IP
for index in "${!OLD_IP_LIST[@]}"; do
  old_ip="${OLD_IP_LIST[index]}"
  temp_ip="${TEMP_IP_LIST[index]}"
  echo "Replacing $old_ip with temporary IP $temp_ip"
  ssh root@"$new_ip" "
    sed -i 's/$old_ip/$temp_ip/' /data/database/install/data/dn/pg_hba.conf && \
    sed -i 's/$old_ip/$temp_ip/' /data/database/install/data/dn/postgresql.conf
  "
done

# 然后将临时 IP 替换为新 IP
for index in "${!TEMP_IP_LIST[@]}"; do
  temp_ip="${TEMP_IP_LIST[index]}"
  new_ip="${NEW_IP_LIST[index]}"
  echo "Replacing temporary IP $temp_ip with new IP $new_ip"
  ssh root@"$new_ip" "
    sed -i 's/$temp_ip/$new_ip/' /data/database/install/data/dn/pg_hba.conf && \
    sed -i 's/$temp_ip/$new_ip/' /data/database/install/data/dn/postgresql.conf
  "
done

echo "IP replacement completed."
sudo -i -u gbase gs_om -t generateconf -X /home/gbase/cluster.xml --distribute
