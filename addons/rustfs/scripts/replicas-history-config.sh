#!/bin/sh

replicas_history_file="/rustfs-config/RUSTFS_REPLICAS_HISTORY"

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
  name: {{ .RUSTFS_COMPONENT_NAME }}-rustfs-configuration
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
    max=$(echo "$cur" | tr ',' '\n' | awk 'BEGIN{m=0} {if($1+0>m)m=$1+0} END{print m}')
    if [ "$replicas" -le "$max" ]; then
      printf "[%s]" "$cur"
    else
      printf "[%s,%s]" "$cur" "$replicas"
    fi
  fi
}

update_configmap_and_sync_to_local_file() {
  namespace={{ .CLUSTER_NAMESPACE }}
  name={{ .RUSTFS_COMPONENT_NAME }}-rustfs-configuration
  key="RUSTFS_REPLICAS_HISTORY"
  replicas="$RUSTFS_COMP_REPLICAS"

  create_cm_if_not_exist "$name" "$namespace"

  cur=$(get_cm_key_value "$name" "$namespace" "$key")
  new=$(get_cm_key_new_value "$cur" "$replicas")

  update_cm_key_value "$name" "$namespace" "$key" "$new"
  echo "configmap/$name updated successfully with $key=$new"

  echo $new >> $replicas_history_file
  echo "the new value $new has been written to the local file $replicas_history_file"
}

# This is magic for shellspec ut framework.
${__SOURCED__:+false} : || return 0

# main
update_configmap_and_sync_to_local_file
