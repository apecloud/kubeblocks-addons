#!/bin/bash

# Initialize table header
echo "| NAME | APP-VERSION | DESCRIPTION |"
echo "| ---- | --------- | ----------- |"

# Traverse and sort directories
for d in $(find . -type d ! -name "*cluster" -not -name "common" -not -name "kblib" -not -name "neonvm" | sort); do
  # Check if Chart.yaml file exists
  if [[ -f "$d/Chart.yaml" ]]; then
    # Use yq to read fields
    name=$(yq e '.name' $d/Chart.yaml)
    description=$(yq e '.description' $d/Chart.yaml)
    dir_name=$(basename $d)
    helm dependency build addons/$dir_name --skip-refresh > /dev/null 2>&1
    appVersion=$(helm template addon addons/$dir_name | grep -A 5 -B 1 'kind: ClusterVersion' | grep '  name:' | awk '{print $2}' | cut -d '-' -f 2- | sort | tr '\n' ',' | sed 's/,$//' | sed 's/,/<br>/g')

    # Output as Markdown table row
    echo "| $name | $appVersion | $description"
  fi
done