#!/bin/sh

replicas_history_file="/rustfs-config/RUSTFS_REPLICAS_HISTORY"

create_cm_if_not_exist() {
  name="$1"
  namespace="$2"

  existing=$(kubectl get configmaps "$name" -n "$namespace" --ignore-not-found -o name) || {
    echo "Failed to check ConfigMap $namespace/$name." >&2
    return 1
  }
  if [ -z "$existing" ]; then
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
    create_status=$?
    if [ "$create_status" -ne 0 ]; then
      existing=$(kubectl get configmaps "$name" -n "$namespace" --ignore-not-found -o name) || existing=""
      if [ -n "$existing" ]; then
        return 0
      fi
      echo "Failed to create ConfigMap $namespace/$name." >&2
      return "$create_status"
    fi
  fi
}

get_cm_key_value() {
  name="$1"
  namespace="$2"
  key="$3"

  value=$(kubectl get configmaps "$name" -n "$namespace" -o jsonpath="{.data.$key}") || {
    echo "Failed to read $key from ConfigMap $namespace/$name." >&2
    return 1
  }
  printf '%s' "$value" | tr -d '[]'
}

update_cm_key_value() {
  name="$1"
  namespace="$2"
  key="$3"
  new_value="$4"

  kubectl patch configmap "$name" -n "$namespace" --type strategic \
    -p "{\"data\":{\"$key\":\"$new_value\"}}" || {
    echo "Failed to update $key in ConfigMap $namespace/$name." >&2
    return 1
  }
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

  create_cm_if_not_exist "$name" "$namespace" || return $?

  cur=$(get_cm_key_value "$name" "$namespace" "$key") || return $?
  new=$(get_cm_key_new_value "$cur" "$replicas")

  update_cm_key_value "$name" "$namespace" "$key" "$new" || return $?
  echo "configmap/$name updated successfully with $key=$new"

  printf '%s\n' "$new" >>"$replicas_history_file" || {
    echo "Failed to write $key to local file $replicas_history_file." >&2
    return 1
  }
  echo "the new value $new has been written to the local file $replicas_history_file"
}

# This is magic for shellspec ut framework.
${__SOURCED__:+false} : || return 0

# main
update_configmap_and_sync_to_local_file
