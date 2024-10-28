#!/bin/bash

# shellcheck disable=SC2154
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
 # when running in non-unit test mode, set the options "set -ex".
 set -ex;
}

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/kb-scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

# Merge configuration files
merge_configs() {
  python3 /kb-scripts/merge_pulsar_config.py conf/bookkeeper.conf /opt/pulsar/conf/bookkeeper.conf
  bin/apply-config-from-env.py conf/bookkeeper.conf
}

# Retrieve directory value from the configuration file
get_directory() {
  local key="$1"
  grep "${key}" /pulsar/conf/bookkeeper.conf | grep -v '#' | cut -d '=' -f 2
}

# Create necessary directories
create_directories() {
  local journal_dir="$1"
  local ledger_dir="$2"
  mkdir -p "${journal_dir}/current" && mkdir -p "${ledger_dir}/current"
}

# Check if both directories are empty
check_empty_directories() {
  local journal_dir="$1"
  local ledger_dir="$2"
  [[ -z $(ls -A "${journal_dir}/current") && -z $(ls -A "${ledger_dir}/current") ]]
}

# Handle the case when both directories are empty
handle_empty_directories() {
  echo "journalRes and ledgerRes directory is empty, check whether the remote cookies is empty either"
  # check env BOOKKEEPER_POD_FQDN_LIST and CURRENT_POD_NAME
  if is_empty "$BOOKKEEPER_POD_FQDN_LIST" || is_empty "$CURRENT_POD_NAME" || is_empty "${zkServers}"; then
    echo "Error: BOOKKEEPER_POD_FQDN_LIST or CURRENT_POD_NAME or zkServers is empty. Exiting." >&2
    return 1
  fi

  local host_ip_port
  host_ip_port=$(get_target_pod_fqdn_from_pod_fqdn_vars "$BOOKKEEPER_POD_FQDN_LIST" "$CURRENT_POD_NAME")
  if is_empty "$host_ip_port"; then
    echo "Error: Failed to get current pod: $CURRENT_POD_NAME fqdn from bookkeeper pod fqdn list: $BOOKKEEPER_POD_FQDN_LIST. Exiting." >&2
    return 1
  fi

  local zkLedgersRootPath
  zkLedgersRootPath=$(get_directory 'zkLedgersRootPath')
  local zNode="${zkLedgersRootPath}/cookies/${host_ip_port}"

  if zkURL="${zkServers}" python3 /kb-scripts/zookeeper.py get "${zNode}"; then
    echo "Warning: exist redundant bookieID ${zNode}"
    zkURL="${zkServers}" python3 /kb-scripts/zookeeper.py delete "${zNode}"
  fi
  return 0
}

start_bookies() {
  merge_configs

  local journalDirectories
  local ledgerDirectories
  journalDirectories=$(get_directory 'journalDirectories')
  ledgerDirectories=$(get_directory 'ledgerDirectories')

  create_directories "${journalDirectories}" "${ledgerDirectories}"

  if check_empty_directories "${journalDirectories}" "${ledgerDirectories}"; then
      if ! handle_empty_directories; then
        echo "Error: Failed to handle empty directories. Exiting." >&2
        exit 1
      fi
  fi

  OPTS="${OPTS} -Dlog4j2.formatMsgNoLookups=true"
  export OPTS
  exec bin/pulsar bookie
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
start_bookies