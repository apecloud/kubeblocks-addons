#!/bin/bash

replicas_history_file="/minio-config/MINIO_REPLICAS_HISTORY"
bucket_dir="/data"

init_buckets() {
  local buckets=$1
  IFS=',' read -ra BUCKET_ARRAY <<< "$buckets"
  for bucket in "${BUCKET_ARRAY[@]}"; do
    directory="$bucket_dir/$bucket"
    if mkdir -p "$directory"; then
      echo "Successfully init bucket: $directory"
    else
      echo "Failed to init bucket: $directory"
    fi
  done
}

read_replicas_history() {
  local file=$1
  content=$(cat "$file")
  content=$(echo "$content" | tr -d '[]')
  IFS=',' read -r -a replicas <<< "$content"
  echo "${replicas[@]}"
}

generate_server_pool() {
  local replicas=("$@")
  local server=""
  for ((i=0; i < ${#replicas[@]}; i++)); do
    if [ $i -eq 0 ]; then
      cur=${replicas[i]}
      server+=" $HTTP_PROTOCOL://$MINIO_COMPONENT_NAME-{0...$((cur-1))}.$MINIO_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN/data"
    else
      prev=${replicas[i-1]}
      cur=${replicas[i]}
      server+=" $HTTP_PROTOCOL://$MINIO_COMPONENT_NAME-{$((prev))...$((cur-1))}.$MINIO_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN/data"
    fi
  done
  echo "$server"
}

startup() {
  if [ ! -f "$replicas_history_file" ]; then
    echo "minio config don't existed"
    exit 1
  fi

  buckets="$MINIO_BUCKETS"
  if [ -n "$buckets" ]; then
    init_buckets "$buckets"
  fi

  mapfile -t replicas < <(read_replicas_history "$replicas_history_file")
  server=$(generate_server_pool "${replicas[@]}")
  echo "the minio server pool is $server"

  cmd="/usr/bin/docker-entrypoint.sh minio server $server -S $CERTS_PATH --address :$MINIO_API_PORT --console-address :$MINIO_CONSOLE_PORT"
  echo "Starting minio server with command: $cmd"
  eval "$cmd"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
startup