#!/bin/bash

get_current_cm_key_value() {
  local name=$1
  local namespace=$2
  local key=$3

  kubectl get configmaps "$name" -n "$namespace" -o jsonpath="{.data.$key}" | tr -d '[]'
}

update_cm_key_value() {
  local name=$1
  local namespace=$2
  local key=$3
  local new_value=$4

  kubectl patch configmap "$name" -n "$namespace" --type strategic -p "{\"data\":{\"$key\":\"$new_value\"}}"
}

get_cm_key_new_value() {
  local cur=$1
  local replicas=$2

  if [[ -z "$cur" ]]; then
    echo "[$replicas]"
  else
    IFS=',' read -ra array <<< "$cur"
    last=${array[-1]}
    if [[ "$last" == "$replicas" ]]; then
      echo "[$cur]"
    else
      echo "[$cur,$replicas]"
    fi
  fi
}

update_configmap() {
  local name="$MINIO_COMPONENT_NAME-minio-configuration"
  local namespace="$CLUSTER_NAMESPACE"
  local key="MINIO_REPLICAS_HISTORY"
  local replicas="$MINIO_COMP_REPLICAS"

  cur=$(get_current_cm_key_value "$name" "$namespace" "$key")
  new=$(get_cm_key_new_value "$cur" "$replicas")

  update_cm_key_value "$name" "$namespace" "$key" "$new"
  echo "ConfigMap $name updated successfully with $key=$new"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
update_configmap