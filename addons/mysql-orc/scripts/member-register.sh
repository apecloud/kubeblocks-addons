#!/bin/bash

# Capture the JSON output from curl
data=$(curl http://orc-cluster-orchestrator-orchestrator:80/api/cluster/alias/10.0.135.74%3A3306)

# Loop through each line of the JSON output
while read -r line; do
  # Check if the line contains "MasterKey": {}
  if [[ "$line" =~ "MasterKey": \{\} ]]; then
    # Extract the Key element (assuming it's a string)
    key=$(echo "$line" | awk -F'"' '{print $4}')
    echo "$key"
  fi
done <<< "$data"