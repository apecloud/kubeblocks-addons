#!/bin/sh

get_current_cm_key_value() {
  name="$1"
  namespace="$2"
  key="$3"

  kubectl get configmaps "$name" -n "$namespace" -o jsonpath="{.data.$key}" | tr -d '[]'
}

update_cm_key_value() {
  name="$1"
  namespace="$2"
  key="$3"
  new_value="$4"

  kubectl patch configmap "$name" -n "$namespace" --type strategic -p "{\"data\":{\"$key\":\"$new_value\"}}"
}

get_cm_key_new_value() {
  cur="$1"
  replicas="$2"

  if [ -z "$cur" ]; then
    printf "[%s]" "$replicas"
  else
    last=$(echo "$cur" | awk -F, '{print $NF}')
    if [ "$last" = "$replicas" ]; then
      printf "[%s]" "$cur"
    else
      printf "[%s,%s]" "$cur" "$replicas"
    fi
  fi
}

update_configmap() {
  name="$MINIO_COMPONENT_NAME-minio-configuration"
  namespace="$CLUSTER_NAMESPACE"
  key="MINIO_REPLICAS_HISTORY"
  replicas="$MINIO_COMP_REPLICAS"

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