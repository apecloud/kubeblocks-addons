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
    appVersion=$(yq e '.appVersion' $d/Chart.yaml)

    # Output as Markdown table row
    echo "| $name | $appVersion | $description"
  fi
done