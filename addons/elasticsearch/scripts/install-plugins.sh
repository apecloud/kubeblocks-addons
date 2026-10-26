#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

src_plugins_dir=${ES_PLUGIN_SOURCE_DIR:-/tmp/plugins}
dst_plugins_dir=${ES_PLUGIN_TARGET_DIR:-/usr/share/elasticsearch/plugins}
plugin_bin=${ELASTICSEARCH_PLUGIN_BIN:-/usr/share/elasticsearch/bin/elasticsearch-plugin}
require_versioned_plugins=${REQUIRE_VERSIONED_PLUGINS:-false}
required_plugin_dirs=${REQUIRED_PLUGIN_DIRS:-"ik pinyin"}
required_plugin_names=${REQUIRED_PLUGIN_NAMES:-"analysis-ik analysis-pinyin"}

fail() {
  echo "$*" >&2
  exit 1
}

if [ ! -d "${src_plugins_dir}" ]; then
  if [ "${require_versioned_plugins}" = "true" ]; then
    fail "required plugin source directory is missing: ${src_plugins_dir}"
  fi
  echo "no plugins to install"
  exit 0
fi

if [ -z "${ELASTICSEARCH_VERSION:-}" ]; then
  fail "ELASTICSEARCH_VERSION is not set"
fi

version_plugins_dir="${src_plugins_dir}/${ELASTICSEARCH_VERSION}"

if [ ! -d "${version_plugins_dir}" ]; then
  if [ "${require_versioned_plugins}" = "true" ]; then
    fail "required plugin directory is missing: ${version_plugins_dir}"
  fi
  echo "No plugin directory found for version ${ELASTICSEARCH_VERSION}"
  exit 0
fi

validate_required_plugins() {
  local plugin descriptor descriptor_version

  for plugin in ${required_plugin_dirs}; do
    descriptor="${version_plugins_dir}/${plugin}/plugin-descriptor.properties"
    if [ ! -d "${version_plugins_dir}/${plugin}" ]; then
      fail "required plugin ${plugin} is missing for Elasticsearch ${ELASTICSEARCH_VERSION}"
    fi
    if [ ! -f "${descriptor}" ]; then
      fail "required plugin ${plugin} descriptor is missing"
    fi
    descriptor_version=$(sed -n 's/^elasticsearch[.]version=//p' "${descriptor}" | head -n 1)
    if [ "${descriptor_version}" != "${ELASTICSEARCH_VERSION}" ]; then
      fail "${plugin} descriptor targets ${descriptor_version:-<empty>}, expected ${ELASTICSEARCH_VERSION}"
    fi
  done
}

copy_install_plugin() {
  local plugin_dir plugin_name
  plugin_dir=$1
  plugin_name=$(basename "${plugin_dir}")
  if [ -d "${dst_plugins_dir}/${plugin_name}" ]; then
    echo "plugin ${plugin_name} already exists"
    return
  fi
  cp -r "${plugin_dir}" "${dst_plugins_dir}/${plugin_name}"
  echo "successfully installed plugin ${plugin_name}"
}

verify_installed_plugins() {
  local installed plugin_name
  installed=$(${plugin_bin} list)
  for plugin_name in ${required_plugin_names}; do
    if ! printf '%s\n' "${installed}" | grep -Fxq "${plugin_name}"; then
      fail "required Elasticsearch plugin ${plugin_name} is not installed"
    fi
  done
  echo "verified required Elasticsearch plugins: ${required_plugin_names}"
}

echo "Installing plugins for Elasticsearch version ${ELASTICSEARCH_VERSION}"
mkdir -p "${dst_plugins_dir}"

if [ "${require_versioned_plugins}" = "true" ]; then
  validate_required_plugins
fi

for plugin_dir in "${version_plugins_dir}"/*/; do
  if [ -d "${plugin_dir}" ]; then
    copy_install_plugin "${plugin_dir}"
  fi
done

if [ "${require_versioned_plugins}" = "true" ]; then
  verify_installed_plugins
fi
