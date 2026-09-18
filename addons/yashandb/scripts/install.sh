#!/usr/bin/env bash
#
# Install and configure YASDB environment

# This is magic for shellspec ut framework. "test" is a `test [expression]` well known as a shell command.
# Normally test without [expression] returns false. It means that __() { :; }
# function is defined if this script runs directly.
#
# shellspec overrides the test command and returns true *once*. It means that
# __() function defined internally by shellspec is called.
#
# In other words. If not in test mode, __ is just a comment. If test mode, __
# is a interception point.
# you should set ut_mode="true" when you want to run the script in shellspec file.
#
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  set -exuo pipefail;
}

# Default configurations
WORK_DIR=${WORK_DIR:-/home/yashan}
SCRIPTS_DIR="/home/yashan/kbscripts"

# Config file paths
YASDB_TEMP_FILE="${YASDB_MOUNT_HOME}/.temp.ini"
YASDB_INSTALL_FILE="${YASDB_MOUNT_HOME}/install.ini"
YASDB_CONFIG="${YASDB_CONFIG:-}"

# Setup environment file paths
setup_env_paths() {
  YASDB_ENV_FILE="${YASDB_HOME}/conf/yasdb.bashrc"
  BASHRC_FILE=~/.bashrc
}

# Copy and process install file
setup_install_file() {
  if [ ! -f "$YASDB_INSTALL_FILE" ]; then
    cp "/home/yashan/kbconfigs/install.ini" "${YASDB_INSTALL_FILE}"
  fi

  grep "=" "${YASDB_INSTALL_FILE}" > "${YASDB_TEMP_FILE}"

  # shellcheck disable=SC1090
  source "${YASDB_TEMP_FILE}"
  # 2026-06-22 Reason: YASDB_DATA is defined by the generated temp file, not before it; Purpose: detect an existing database correctly and avoid re-running create database against populated PVCs.
  YASDB_CONFIG="${YASDB_DATA}/config/yasdb.ini"
  if [ -f "$YASDB_CONFIG" ]; then
    sync_runtime_config_file
  fi
}

sync_runtime_config_file() {
  local key value persisted_pairs

  persisted_pairs="${YASDB_MOUNT_HOME}/.persisted-install-pairs"
  grep "=" "$YASDB_INSTALL_FILE" >"$persisted_pairs"
  while IFS='=' read -r key value; do
    [ -n "$key" ] || continue
    case "$key" in YASDB_HOME | YASDB_DATA | REDO_FILE_SIZE | REDO_FILE_NUM | INSTALL_SIMPLE_SCHEMA_SALES | NLS_CHARACTERSET) continue ;; esac
    if grep -qE "^${key}=" "$YASDB_CONFIG"; then
      sed -i "s|^${key}=.*|${key}=${value}|" "$YASDB_CONFIG"
    else
      printf '%s=%s\n' "$key" "$value" >>"$YASDB_CONFIG"
    fi
  done <"$persisted_pairs"
  rm -f "$persisted_pairs"
}

# Generate environment file content
generate_env_content() {
  cat >"${YASDB_ENV_FILE}" <<EOF
export YASDB_HOME=$YASDB_HOME
export YASDB_DATA=$YASDB_DATA
export PATH=\$YASDB_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$YASDB_HOME/lib:\$LD_LIBRARY_PATH
EOF
}

# Update bashrc file
update_bashrc() {
  # Remove old entry if exists
  sed -i '/'"source ${YASDB_HOME//\//\\/}\/conf\/yasdb.bashrc"'/d' "$BASHRC_FILE"

  # Add new entry
  cat >>"$BASHRC_FILE" <<EOF
[ -f $YASDB_ENV_FILE ] && source $YASDB_ENV_FILE
EOF
}

# 2026-06-17 Reason: support official YashanDB images that keep the database runtime in a nested tarball; Purpose: preserve KubeBlocks-managed startup while making the image layout compatible with addon scripts.
prepare_runtime_source_dir() {
  local runtime_cache_dir outer_cache_dir image_package database_package

  if [ -d "$WORK_DIR/bin" ] && [ -d "$WORK_DIR/conf" ] && [ -d "$WORK_DIR/admin" ]; then
    echo "$WORK_DIR"
    return 0
  fi

  image_package=$(find "$WORK_DIR" -maxdepth 1 -type f -name 'yashandb-*-linux-*.tar.gz' | head -n 1)
  if [ -z "$image_package" ]; then
    echo "YASDB runtime directories or image package are missing under ${WORK_DIR}" >&2
    return 1
  fi

  runtime_cache_dir="${YASDB_MOUNT_HOME}/.runtime-cache"
  outer_cache_dir="${runtime_cache_dir}/outer"

  if [ ! -d "${runtime_cache_dir}/bin" ] || [ ! -d "${runtime_cache_dir}/conf" ] || [ ! -d "${runtime_cache_dir}/admin" ]; then
    rm -rf "$runtime_cache_dir"
    mkdir -p "$outer_cache_dir"
    tar -zxf "$image_package" -C "$outer_cache_dir"

    database_package=$(find "$outer_cache_dir" -maxdepth 1 -type f -name 'database-*-linux-*.tar.gz' | head -n 1)
    if [ -z "$database_package" ]; then
      echo "database package is missing inside ${image_package}" >&2
      return 1
    fi

    tar -zxf "$database_package" -C "$runtime_cache_dir"
  fi

  echo "$runtime_cache_dir"
}

# Setup YASDB directories
setup_directories() {
  local runtime_source_dir

  runtime_source_dir=$(prepare_runtime_source_dir)

  mkdir -p "$YASDB_HOME"
  cp -ra "$runtime_source_dir"/{admin,bin,conf,gitmoduleversion.dat,include,java,lib,plug-in,scripts} "$YASDB_HOME"

  # 2026-06-17 Reason: official image packages keep regexp/listagg and other plugins outside database-*.tar.gz; Purpose: make the extracted runtime match the plugin paths required during database startup.
  if [ -d "${runtime_source_dir}/outer/plugins" ]; then
    for plugin_package in "${runtime_source_dir}"/outer/plugins/*.tar.gz; do
      [ -f "$plugin_package" ] || continue
      tar -zxf "$plugin_package" -C "$YASDB_HOME"
    done
  fi

  mkdir -p "$YASDB_HOME"/client
  touch "$YASDB_HOME"/client/yasc_service.ini

  mkdir -p "$YASDB_DATA"/{config,data,dbfiles,instance,archive,local_fs,log/{run,audit,trace,alarm,alert,listener},diag/{metadata,hm,blackbox}}
}

# Main installation process
install_yasdb() {
  setup_directories
  setup_env_paths
  generate_env_content
  update_bashrc
  source "$SCRIPTS_DIR/initDB.sh"
}

# Update existing installation
update_yasdb() {
  setup_env_paths
  generate_env_content
  update_bashrc
  source "$SCRIPTS_DIR/startup.sh"
}

main() {
  setup_install_file

  if [ -f "$YASDB_CONFIG" ]; then
    echo "yasdb.ini already exists"
    update_yasdb
  else
    install_yasdb
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

main "$@"
