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

get_cm_key_snapshot() {
  name="$1"
  namespace="$2"
  key="$3"

  value=$(kubectl get configmaps "$name" -n "$namespace" \
    -o "jsonpath={.metadata.resourceVersion}{'\\t'}{.data.$key}") || {
    echo "Failed to read $key from ConfigMap $namespace/$name." >&2
    return 1
  }
  printf '%s' "$value"
}

parse_cm_key_history() {
  raw="$1"

  if [ -z "$raw" ]; then
    return 0
  fi
  case "$raw" in
    \[*\]) value=${raw#\[}; value=${value%\]} ;;
    *) return 1 ;;
  esac
  case "$value" in
    ''|,*|*,|*,,*|*[!0-9,]*) return 1 ;;
  esac

  previous=0
  old_ifs="$IFS"
  IFS=','
  for item in $value; do
    if ! [ "$item" -gt "$previous" ] 2>/dev/null; then
      IFS="$old_ifs"
      return 1
    fi
    previous="$item"
  done
  IFS="$old_ifs"
  printf '%s' "$value"
}

update_cm_key_value() {
  name="$1"
  namespace="$2"
  key="$3"
  new_value="$4"
  resource_version="$5"

  kubectl patch configmap "$name" -n "$namespace" --type strategic \
    -p "{\"metadata\":{\"resourceVersion\":\"$resource_version\"},\"data\":{\"$key\":\"$new_value\"}}"
}

get_cm_key_new_value() {
  cur="$1"
  replicas="$2"

  if [ -z "$cur" ]; then
    printf "[%s]" "$replicas"
  else
    max=${cur##*,}
    if [ "$replicas" -le "$max" ]; then
      printf "[%s]" "$cur"
    else
      printf "[%s,%s]" "$cur" "$replicas"
    fi
  fi
}

get_confirmed_cm_key_value() {
  name="$1"
  namespace="$2"
  key="$3"
  replicas="$4"
  tab=$(printf '\t')

  snapshot=$(get_cm_key_snapshot "$name" "$namespace" "$key") || return $?
  case "$snapshot" in
    *"$tab"*) ;;
    *)
      echo "Failed to parse confirmed $key snapshot from ConfigMap $namespace/$name." >&2
      return 1
      ;;
  esac
  raw_cur=${snapshot#*"$tab"}
  cur=$(parse_cm_key_history "$raw_cur") || {
    echo "Failed to parse confirmed $key history from ConfigMap $namespace/$name." >&2
    return 1
  }
  confirmed=$(get_cm_key_new_value "$cur" "$replicas")
  if [ "$confirmed" != "[$cur]" ]; then
    echo "Confirmed $key in ConfigMap $namespace/$name does not contain replicas $replicas." >&2
    return 1
  fi
  printf '%s' "$confirmed"
}

update_configmap_and_sync_to_local_file() {
  namespace={{ .CLUSTER_NAMESPACE }}
  name={{ .RUSTFS_COMPONENT_NAME }}-rustfs-configuration
  key="RUSTFS_REPLICAS_HISTORY"
  replicas="$RUSTFS_COMP_REPLICAS"

  create_cm_if_not_exist "$name" "$namespace" || return $?

  attempt=1
  max_attempts=5
  tab=$(printf '\t')
  while [ "$attempt" -le "$max_attempts" ]; do
    snapshot=$(get_cm_key_snapshot "$name" "$namespace" "$key") || return $?
    case "$snapshot" in
      *"$tab"*) ;;
      *)
        echo "Failed to parse $key snapshot from ConfigMap $namespace/$name." >&2
        return 1
        ;;
    esac
    resource_version=${snapshot%%"$tab"*}
    raw_cur=${snapshot#*"$tab"}
    cur=$(parse_cm_key_history "$raw_cur") || {
      echo "Failed to parse $key history from ConfigMap $namespace/$name." >&2
      return 1
    }
    new=$(get_cm_key_new_value "$cur" "$replicas")

    if update_cm_key_value "$name" "$namespace" "$key" "$new" "$resource_version"; then
      new=$(get_confirmed_cm_key_value "$name" "$namespace" "$key" "$replicas") || return $?
      break
    fi
    attempt=$((attempt + 1))
  done
  if [ "$attempt" -gt "$max_attempts" ]; then
    echo "Failed to update $key in ConfigMap $namespace/$name after $max_attempts attempts." >&2
    return 1
  fi
  echo "configmap/$name updated successfully with $key=$new"

  printf '%s\n' "$new" >"$replicas_history_file" || {
    echo "Failed to write $key to local file $replicas_history_file." >&2
    return 1
  }
  echo "the new value $new has been written to the local file $replicas_history_file"
}

# This is magic for shellspec ut framework.
${__SOURCED__:+false} : || return 0

# main
update_configmap_and_sync_to_local_file
