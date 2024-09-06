#!/bin/bash

# Initialize table header
echo "| NAME | DESCRIPTION | Maintainers |"
echo "| ---- | ----------- | ----------- |"

# Traverse and sort directories
# for d in $(find . -type d ! -name "*cluster" -not -name "common" -not -name "kblib" -not -name "neonvm" | sort); do
for d in $(find ./addons -type d  -not -name "common" -not -name "kblib" -not -name "neonvm" | sort); do
  # Check if Chart.yaml file exists
  if [[ -f "$d/Chart.yaml" ]]; then
    # Use yq to read fields
    name=$(yq e '.name' $d/Chart.yaml)
    description=$(yq e '.description' $d/Chart.yaml)

    # dir_name=$(basename $d)
    # helm dependency build addons/$dir_name --skip-refresh > /dev/null 2>&1
    # version_lines=$(helm template addon addons/$dir_name | grep -A 5 'kind: ClusterVersion' | grep '  name:' | awk '{print $2}' | cut -d '-' -f 2- | sort)
    # versions=""
    # while IFS= read -r line
    # do
    #   if [[ $line == v* ]]; then
    #     line=${line:1}
    #   fi
    #   versions+="${line}<br>"
    # done <<<"$version_lines"
    # versions=${versions%<br>}

    # Output as Markdown table row
    maintainers=$(yq e '.maintainers[].name' $d/Chart.yaml)
    maintainers=$(echo $maintainers | tr '\r' ' ')
    echo "| $name | $description | $maintainers |"
  fi
done