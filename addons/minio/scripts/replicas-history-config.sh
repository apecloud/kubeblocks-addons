#!/bin/sh

replicas_history_file="/minio-config/MINIO_REPLICAS_HISTORY"

create_cm_if_not_exist() {
  name="$1"
  namespace="$2"

  kubectl get configmaps "$name" -n "$namespace"
  if [ $? -ne 0 ]; then
    cat <<EOF | kubectl create -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: {{ .CLUSTER_NAMESPACE }}
  name: {{ .MINIO_COMPONENT_NAME }}-minio-configuration
  labels:
    app.kubernetes.io/managed-by: kubeblocks
    app.kubernetes.io/instance: {{ .CLUSTER_NAME }}
    apps.kubeblocks.io/component-name: {{ .CLUSTER_COMPONENT_NAME }}
EOF
  fi
}

get_cm_key_value() {
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

update_configmap_and_sync_to_local_file() {
  namespace={{ .CLUSTER_NAMESPACE }}
  name={{ .MINIO_COMPONENT_NAME }}-minio-configuration
  key="MINIO_REPLICAS_HISTORY"
  replicas="$MINIO_COMP_REPLICAS"

  create_cm_if_not_exist "$name" "$namespace"

  cur=$(get_cm_key_value "$name" "$namespace" "$key")
  new=$(get_cm_key_new_value "$cur" "$replicas")

  update_cm_key_value "$name" "$namespace" "$key" "$new"
  echo "configmap/$name updated successfully with $key=$new"

  echo $new >> $replicas_history_file
  echo "the new value $new has been written to the local file $replicas_history_file"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
update_configmap_and_sync_to_local_file
