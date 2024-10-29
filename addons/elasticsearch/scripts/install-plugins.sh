#!/usr/bin/env bash

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

init_vars() {
  SRC_PLUGINS_DIR="/tmp/plugins"
  DST_PLUGINS_DIR="/usr/share/elasticsearch/plugins"
  ES_PLUGIN_CMD="/usr/share/elasticsearch/bin/elasticsearch-plugin"

  export SRC_PLUGINS_DIR
  export DST_PLUGINS_DIR
  export ES_PLUGIN_CMD
}

check_src_dir() {
  if [[ ! -d "$SRC_PLUGINS_DIR" ]]; then
    echo "no plugins to install"
    exit 0
  fi
}

is_archive_file() {
  local plugin="$1"
  [[ "$plugin" =~ \.(zip|gz|tar\.gz)$ ]]
}

native_install_plugin() {
  local plugin_path="$1"
  local plugin_name
  plugin_name=$(basename "$plugin_path")
  local output

  if output=$("$ES_PLUGIN_CMD" install -b "$plugin_path" 2>&1); then
    echo "successfully installed plugin $plugin_name"
    return 0
  fi

  if echo "$output" | grep -q 'already exists'; then
    echo "plugin $plugin_name already exists"
    return 0
  fi

  echo "failed to install plugin $plugin_name"
  echo "$output"
  return 1
}

copy_install_plugin() {
  local plugin_path="$1"
  local plugin_name
  plugin_name=$(basename "$plugin_path")
  local dst_path="$DST_PLUGINS_DIR/$plugin_name"

  if [[ -d "$dst_path" ]]; then
    echo "plugin $plugin_name already exists"
    return 0
  fi

  cp -r "$plugin_path" "$DST_PLUGINS_DIR"
  echo "successfully installed plugin $plugin_name"
}

install_plugin() {
  local plugin_path="$1"
  local plugin_name
  plugin_name=$(basename "$plugin_path")

  echo "installing plugin $plugin_name"

  if is_archive_file "$plugin_name"; then
    native_install_plugin "$plugin_path"
  else
    copy_install_plugin "$plugin_path"
  fi
}

install_all_plugins() {
  local plugin
  while IFS= read -r plugin; do
    [[ -e "$plugin" ]] && install_plugin "$plugin"
  done < <(find "$SRC_PLUGINS_DIR" -maxdepth 1 -mindepth 1)
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
init_vars
check_src_dir
install_all_plugins
