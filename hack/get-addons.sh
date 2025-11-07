#!/bin/bash

# Initialize table header
echo "| NAME | VERSIOINS | DESCRIPTION | MAINTAINERS |"
echo "| ---- | ---- | ----------- | ----------- |"

# Traverse and sort directories
# for d in $(find . -type d ! -name "*cluster" -not -name "common" -not -name "kblib" -not -name "neonvm" | sort); do
for d in $(find ./addons -type d  -not -name "common" -not -name "kblib" -not -name "neonvm" | sort); do
  # Check if Chart.yaml file exists
  if [[ -f "$d/Chart.yaml" ]]; then
    # Use yq to read fields
    name=$(yq e '.name' $d/Chart.yaml)
    description=$(yq e '.description' $d/Chart.yaml)
    dir_name=$(basename $d)

    helm dependency build addons/$dir_name --skip-refresh > /dev/null 2>&1
    helm template addon addons/$dir_name --dependency-update > /tmp/rendered.yaml

    # prase from ComponentVersion
    version_lines=$(cat "/tmp/rendered.yaml" | yq e '. | select(.kind == "ComponentVersion")'  | yq '.metadata.name + "-" +.spec.releases[].serviceVersion' -N | sort | uniq)
    # if version_lines is empty, try to get version from ComponentDefinition
    if [[ -z $version_lines ]]; then
      version_lines=$(cat "/tmp/rendered.yaml"  | yq e '. | select(.kind == "ComponentDefinition")'  | yq '.spec.serviceKind + "-" +.spec.serviceVersion' -N | sort | uniq)
    fi
    # if version_lines is empty, try to get version from List of ComponentDefinition
    if [[ -z $version_lines ]]; then
      version_lines=$(cat "/tmp/rendered.yaml"  | yq e '. | select(.kind == "List") | .items[0] | select(.kind == "ComponentDefinition") | .spec.serviceKind + "-" +.spec.serviceVersion' -N | sort | uniq)
    fi
    # if version_lines is empty, try to get version from clusterdefintioin
    if [[ -z $version_lines ]]; then
      version_lines=$(cat "/tmp/rendered.yaml"  | yq  e '. | select(.kind == "ClusterDefinition") | .spec.componentDefs[].podSpec.containers[0].image | sub(".*/", "") | sub(":", "-")' -N | sort | uniq)
    fi

    # version_lines=$(helm template addon addons/$dir_name | grep -A 5 'kind: ComponentVersion' | grep '  name:' | awk '{print $2}' | cut -d '-' -f 2- | sort)
    versions=""
    while IFS= read -r line
    do
      if [[ $line == v* ]]; then
        line=${line:1}
      fi
      versions+="${line}<br>"
    done <<<"$version_lines"
    versions=${versions%<br>}
    # echo $versions

    # Output as Markdown table row
    maintainers=$(yq e '.maintainers[].name' $d/Chart.yaml)
    maintainers=$(echo $maintainers | tr '\r' ' ')
    echo "| $name | $versions | $description | $maintainers |"
  fi
done