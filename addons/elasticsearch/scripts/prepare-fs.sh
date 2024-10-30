#!/usr/bin/env bash

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -exu".
  set -exu;
}

ES_HOME="/usr/share/elasticsearch"
LICENSE_FILE="${ES_HOME}/LICENSE.txt"
MOUNT_LOCAL_CONFIG="/mnt/local-config"
MOUNT_LOCAL_PLUGINS="/mnt/local-plugins"
MOUNT_LOCAL_BIN="/mnt/local-bin"
MOUNT_REMOTE_CONFIG="/mnt/remote-config"

check_distribution() {
  if [[ ! -f ${LICENSE_FILE} || $(grep -Exc "ELASTIC LICENSE AGREEMENT|Elastic License 2.0" ${LICENSE_FILE}) -ne 1 ]]; then
    >&2 echo "unsupported_distribution"
    return 1
  fi
  return 0
}

get_duration() {
  local start=$1
  local end
  end=$(date +%s)
  echo $((end-start))
}

copy_directory_contents() {
  local src_dir=$1
  local dest_dir=$2
  local dir_name=$3

  if [[ -z "$(ls -A ${src_dir}/${dir_name})" ]]; then
    echo "Empty dir ${src_dir}/${dir_name}"
    return 0
  fi

  echo "Copying ${src_dir}/${dir_name}/* to ${dest_dir}/"
  # Use "yes" and "-f" as we want the init container to be idempotent and not to fail when executed more than once.
  yes | cp -avf ${src_dir}/${dir_name}/* ${dest_dir}/
}

# Persist the content of bin/, config/ and plugins/ to a volume, so installed plugins files can to be used by the ES container
persist_files() {
  local mv_start
  mv_start=$(date +%s)

  copy_directory_contents "${ES_HOME}" "${MOUNT_LOCAL_CONFIG}" "config"
  copy_directory_contents "${ES_HOME}" "${MOUNT_LOCAL_PLUGINS}" "plugins"
  copy_directory_contents "${ES_HOME}" "${MOUNT_LOCAL_BIN}" "bin"

  echo "Files copy duration: $(get_duration ${mv_start}) sec."
}

create_config_links() {
  local ln_start
  ln_start=$(date +%s)

  local config_files=(
    "elasticsearch.yml"
    "log4j2.properties"
  )

  for file in "${config_files[@]}"; do
    echo "Linking ${MOUNT_REMOTE_CONFIG}/${file} to ${MOUNT_LOCAL_CONFIG}/${file}"
    ln -sf "${MOUNT_REMOTE_CONFIG}/${file}" "${MOUNT_LOCAL_CONFIG}/${file}"
  done

  echo "File linking duration: $(get_duration ${ln_start}) sec."
}

prepare_fs() {
  local script_start
  script_start=$(date +%s)

  echo "Starting init script"

  if ! check_distribution; then
    echo "Unsupported distribution"
    exit 42
  fi

  persist_files

  create_config_links

  echo "Init script successful"
  echo "Script duration: $(get_duration ${script_start}) sec."
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
prepare_fs