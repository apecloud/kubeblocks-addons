#!/bin/bash

# Initialize table header
echo "| NAME | DESCRIPTION |"
echo "| ---- | ----------- |"

# Traverse and sort directories
for d in $(find . -type d ! -name "*cluster" -not -name "common" -not -name "kblib" | sort); do
  # Check if Chart.yaml file exists
  if [[ -f "$d/Chart.yaml" ]]; then
    # Use yq to read fields
    name=$(yq e '.name' $d/Chart.yaml)
    description=$(yq e '.description' $d/Chart.yaml)

    # Output as Markdown table row
    echo "| $name | $description |"
  fi
done