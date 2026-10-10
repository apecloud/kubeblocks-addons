#!/bin/sh
set -eu

: "${DOLT_CONFIG_TEMPLATE_PATH:=/kb-config/doltdb/server.yaml}"
: "${DOLT_GENERATED_CONFIG_PATH:=/var/lib/dolt/.kb/server.yaml}"
: "${DOLT_REMOTESAPI_PORT:=50051}"
: "${DOLT_BOOTSTRAP_EPOCH:=1}"
: "${DATA_DIR:=/var/lib/dolt}"

unset_entrypoint_database_init_env() {
  unset DOLT_DATABASE MYSQL_DATABASE
  unset DOLT_USER MYSQL_USER DOLT_PASSWORD MYSQL_PASSWORD DOLT_USER_HOST MYSQL_USER_HOST
}

disable_existing_database_init() {
  database="${DOLT_DATABASE:-${MYSQL_DATABASE:-}}"
  if [ -n "$database" ] && [ -d "${DATA_DIR}/${database}/.dolt" ]; then
    unset_entrypoint_database_init_env
  fi
}

append_cluster_config() {
  : "${CURRENT_POD_NAME:?CURRENT_POD_NAME is required when DOLT_CLUSTER_MODE=true}"
  : "${DOLT_POD_FQDN_LIST:?DOLT_POD_FQDN_LIST is required when DOLT_CLUSTER_MODE=true}"

  old_ifs="$IFS"
  IFS=,
  set -- $DOLT_POD_FQDN_LIST
  IFS="$old_ifs"

  current_ordinal=""
  index=0
  for fqdn do
    case "$fqdn" in
      "$CURRENT_POD_NAME"|"$CURRENT_POD_NAME".*)
        current_ordinal="$index"
        ;;
    esac
    if [ -n "$current_ordinal" ]; then
      break
    fi
    index=$((index + 1))
  done

  if [ -z "$current_ordinal" ]; then
    echo "current pod ${CURRENT_POD_NAME} is not present in DOLT_POD_FQDN_LIST=${DOLT_POD_FQDN_LIST}" >&2
    exit 1
  fi

  if [ "$#" -lt 2 ]; then
    echo "Dolt cluster mode requires at least two pod FQDNs; got ${DOLT_POD_FQDN_LIST}" >&2
    exit 1
  fi

  bootstrap_role="standby"
  if [ "$current_ordinal" -eq 0 ]; then
    bootstrap_role="primary"
  fi

  {
    printf '\ncluster:\n'
    printf '  standby_remotes:\n'
    index=0
    for fqdn do
      if [ "$index" -ne "$current_ordinal" ]; then
        remote_name="${fqdn%%.*}"
        printf '    - name: %s\n' "$remote_name"
        printf '      remote_url_template: http://%s:%s/{database}\n' "$fqdn" "$DOLT_REMOTESAPI_PORT"
      fi
      index=$((index + 1))
    done
    printf '  bootstrap_role: %s\n' "$bootstrap_role"
    printf '  bootstrap_epoch: %s\n' "$DOLT_BOOTSTRAP_EPOCH"
    printf '  remotesapi:\n'
    printf '    port: %s\n' "$DOLT_REMOTESAPI_PORT"
  } >>"$DOLT_GENERATED_CONFIG_PATH"

  if [ "$bootstrap_role" = "standby" ]; then
    unset_entrypoint_database_init_env
  fi
}

mkdir -p "$(dirname "$DOLT_GENERATED_CONFIG_PATH")"
cp "$DOLT_CONFIG_TEMPLATE_PATH" "$DOLT_GENERATED_CONFIG_PATH"

if [ "${DOLT_CLUSTER_MODE:-false}" = "true" ]; then
  append_cluster_config
fi
disable_existing_database_init

exec /usr/local/bin/docker-entrypoint.sh "--config=${DOLT_GENERATED_CONFIG_PATH}"
