#!/bin/bash

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  set -ex
}

declare SPEC_FILE_SOURCE="/config/spec.json"
declare SPEC_FILE_DOCKER_SOURCE="/config/spec.prep.DOCKER.json"
declare PGDATA_DIR="/data/pgdata"
declare SPEC_DIR="/data/spec"
declare SPEC_FILE="/data/spec/spec.json"
declare SPEC_FILE_DOCKER="/data/spec/spec.prep.DOCKER.json"
declare PG_VERSION=14
declare PAGESERVER
declare SAFEKEEPERS

check_required_env() {
  local missing_vars=()

  if [ -z "$NEON_PAGESERVER_POD_FQDN_LIST" ]; then
    missing_vars+=("NEON_PAGESERVER_POD_FQDN_LIST")
  fi
  if [ -z "$NEON_SAFEKEEPERS_POD_FQDN_LIST" ]; then
    missing_vars+=("NEON_SAFEKEEPERS_POD_FQDN_LIST")
  fi
  if [ -z "$NEON_SAFEKEEPERS_PORT" ]; then
    missing_vars+=("NEON_SAFEKEEPERS_PORT")
  fi

  if [ ${#missing_vars[@]} -ne 0 ]; then
    echo "Error: Missing required environment variables: ${missing_vars[*]}" >&2
    return 1
  fi
  return 0
}

setup_directories() {
  if [ ! -d "$PGDATA_DIR" ]; then
    mkdir -p "$PGDATA_DIR" || {
      echo "Failed to create pgdata directory: $PGDATA_DIR" >&2
      return 1
    }
    mkdir -p "$SPEC_DIR" || {
      echo "Failed to create spec directory: $SPEC_DIR" >&2
      return 1
    }
    cp "$SPEC_FILE_DOCKER_SOURCE" "$SPEC_FILE_DOCKER"
    cp "$SPEC_FILE_SOURCE" "$SPEC_FILE"
    chmod +w "$SPEC_FILE_DOCKER"
    chmod +w "$SPEC_FILE"
    return 0
  fi
  echo "$PGDATA_DIR already exists"
  return 0
}

build_pageserver_string() {
  echo "$NEON_PAGESERVER_POD_FQDN_LIST"
}

build_safekeepers_string() {
  local result=""
  local fqdn_list

  IFS=',' read -ra fqdn_list <<< "$NEON_SAFEKEEPERS_POD_FQDN_LIST"

  if [ ${#fqdn_list[@]} -gt 0 ]; then
    result="${fqdn_list[0]}:$NEON_SAFEKEEPERS_PORT"
  fi

  for ((i=1; i<${#fqdn_list[@]}; i++)); do
    result="$result,${fqdn_list[i]}:$NEON_SAFEKEEPERS_PORT"
  done

  echo "$result"
}

wait_for_pageserver() {
  local pageserver="$1"
  if [ -z "$pageserver" ]; then
    echo "Error: Empty pageserver address" >&2
    return 1
  fi

  local first_pageserver
  first_pageserver=$(echo "$pageserver" | cut -d',' -f1)

  echo "Waiting pageserver become ready."
  while ! nc -z "$first_pageserver" "$NEON_PAGESERVER_PGPORT"; do
    sleep 1
  done
  echo "Page server is ready."
}

create_tenant() {
  if [ -n "$TENANT" ]; then
    echo "$TENANT"
    return 0
  fi

  if [ -z "$PAGESERVER" ]; then
    echo "Error: PAGESERVER is not set" >&2
    return 1
  fi

  local first_pageserver
  first_pageserver=$(echo "$PAGESERVER" | cut -d',' -f1)

  local params=(
    -sb
    -X POST
    -H "Content-Type: application/json"
    -d "{}"
    "http://${first_pageserver}:$NEON_PAGESERVER_HTTPPORT/v1/tenant/"
  )

  local response
  response=$(curl "${params[@]}")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Error: Failed to create tenant" >&2
    return 1
  fi

  echo "$response" | tr -d '"'
}

create_timeline() {
  local tenant_id="$1"
  if [ -z "$tenant_id" ]; then
    echo "Error: tenant_id is required" >&2
    return 1
  fi

  local timeline_data

  if [ -n "$TIMELINE" ]; then
    if [ -n "$CREATE_BRANCH" ]; then
      timeline_data="{\"tenant_id\":\"${tenant_id}\", \"pg_version\": ${PG_VERSION}, \"ancestor_timeline_id\":\"${TIMELINE}\"}"
    else
      echo "$TIMELINE"
      return 0
    fi
  else
    timeline_data="{\"tenant_id\":\"${tenant_id}\", \"pg_version\": ${PG_VERSION}}"
  fi

  local first_pageserver
  first_pageserver=$(echo "$PAGESERVER" | cut -d',' -f1)

  local params=(
    -sb
    -X POST
    -H "Content-Type: application/json"
    -d "$timeline_data"
    "http://${first_pageserver}:$NEON_PAGESERVER_HTTPPORT/v1/tenant/${tenant_id}/timeline/"
  )
  local response
  response=$(curl "${params[@]}")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Error: Failed to create timeline" >&2
    return 1
  fi
  echo "$response"
}

update_spec_file() {
  local tenant_id="$1"
  local timeline_id="$2"
  local pageserver="$3"
  local safekeepers="$4"

  if [ -z "$tenant_id" ] || [ -z "$timeline_id" ] || [ -z "$pageserver" ] || [ -z "$safekeepers" ]; then
    echo "Error: Missing required parameters for update_spec_file" >&2
    return 1
  fi

  cp "${SPEC_FILE_DOCKER}" "${SPEC_FILE}" || {
      echo "Error: Failed to copy template file" >&2
      return 1
  }

  sed "s|TENANT_ID|${tenant_id}|g" "${SPEC_FILE}" > "${SPEC_FILE}.tmp" && mv "${SPEC_FILE}.tmp" "${SPEC_FILE}"
  sed "s|TIMELINE_ID|${timeline_id}|g" "${SPEC_FILE}" > "${SPEC_FILE}.tmp" && mv "${SPEC_FILE}.tmp" "${SPEC_FILE}"
  sed "s|PAGESERVER_SPEC|${pageserver}|g" "${SPEC_FILE}" > "${SPEC_FILE}.tmp" && mv "${SPEC_FILE}.tmp" "${SPEC_FILE}"
  sed "s|SAFEKEEPERS_SPEC|${safekeepers}|g" "${SPEC_FILE}" > "${SPEC_FILE}.tmp" && mv "${SPEC_FILE}.tmp" "${SPEC_FILE}"

  rm -f "${SPEC_FILE}.tmp"
  return 0
}

start_compute_node() {
  if [ ! -f "${SPEC_FILE}" ]; then
    echo "Error: Spec file not found: ${SPEC_FILE}" >&2
    return 1
  fi

  /opt/neondatabase-neon/target/release/compute_ctl \
    --pgdata /data/pgdata \
    -C "postgresql://$NEON_COMPUTE_PGUSER@localhost:$NEON_COMPUTE_PGPORT/postgres" \
    -b /opt/neondatabase-neon/pg_install/v14/bin/postgres \
    -S "${SPEC_FILE}"
}

setup_environment() {
  # check required env
  check_required_env || return 1

  # setup directories
  setup_directories || return 1

  # build pageserver and safekeepers string
  PAGESERVER=$(build_pageserver_string)
  if [ -z "$PAGESERVER" ]; then
    echo "Error: Failed to build pageserver string" >&2
    return 1
  fi

  SAFEKEEPERS=$(build_safekeepers_string)
  if [ -z "$SAFEKEEPERS" ]; then
    echo "Error: Failed to build safekeepers string" >&2
    return 1
  fi

  echo "PageServer: ${PAGESERVER}"
  echo "Safekeepers: ${SAFEKEEPERS}"

  wait_for_pageserver "$PAGESERVER" || return 1
}

process_tenant_and_timeline() {
  local tenant_id
  local timeline_id
  local result

  tenant_id=$(create_tenant)
  status=$?
  if [ $status -ne 0 ]; then
    echo "Error: Failed to create tenant" >&2
    return 1
  fi

  result=$(create_timeline "$tenant_id")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Error: Failed to create timeline" >&2
    return 1
  fi

  if [ -z "$TIMELINE" ] || [ -n "$CREATE_BRANCH" ]; then
    echo "$result" | jq .
    echo "Overwrite tenant id and timeline id in spec file"
    tenant_id=$(echo "${result}" | jq -r .tenant_id)
    timeline_id=$(echo "${result}" | jq -r .timeline_id)
  else
    timeline_id=$TIMELINE
  fi

  update_spec_file "$tenant_id" "$timeline_id" "$PAGESERVER" "$SAFEKEEPERS" || return 1
}

show_environment_info() {
  if [ ! -f "${SPEC_FILE}" ]; then
    echo "Error: Spec file not found: ${SPEC_FILE}" >&2
    return 1
  fi

  cat "${SPEC_FILE}"
  echo "Start compute node"
  whoami
  echo "$PWD"
  ls -lah /data
}

main() {
  setup_environment || {
    echo "Error: Failed to setup environment" >&2
    return 1
  }

  process_tenant_and_timeline || {
    echo "Error: Failed to process tenant and timeline" >&2
    return 1
  }

  show_environment_info || {
    echo "Error: Failed to show environment info" >&2
    return 1
  }

  start_compute_node || {
    echo "Error: Failed to start compute node" >&2
    return 1
  }
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
main