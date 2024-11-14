#!/usr/bin/env bash
#
# Install and configure YASDB environment

set -euo pipefail

# Default configurations
readonly WORK_DIR=${WORK_DIR:-/home/yashan}
readonly SCRIPTS_DIR="/home/yashan/kbscripts"

# Config file paths
readonly YASDB_TEMP_FILE="${YASDB_MOUNT_HOME}/.temp.ini"
readonly YASDB_INSTALL_FILE="${YASDB_MOUNT_HOME}/install.ini"
readonly YASDB_CONFIG="${YASDB_DATA}/config/yasdb.ini"

# Setup environment file paths
setup_env_paths() {
  readonly YASDB_ENV_FILE="${YASDB_HOME}/conf/yasdb.bashrc"
  readonly BASHRC_FILE=~/.bashrc
}

# Copy and process install file
setup_install_file() {
  if [ ! -f "$YASDB_INSTALL_FILE" ]; then
    cp "/home/yashan/kbconfigs/install.ini" "${YASDB_INSTALL_FILE}"
    grep "=" "${YASDB_INSTALL_FILE}" > "${YASDB_TEMP_FILE}"
  fi

  # shellcheck disable=SC1090
  source "${YASDB_TEMP_FILE}"
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

# Setup YASDB directories
setup_directories() {
  mkdir -p "$YASDB_HOME"
  cp -ra "$WORK_DIR"/{admin,bin,conf,gitmoduleversion.dat,include,java,lib,plug-in,scripts} "$YASDB_HOME"

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

main "$@"