#!/usr/bin/env bash

set -o errexit

src_plugins_dir=/tmp/plugins
dst_plugins_dir=/usr/share/elasticsearch/plugins

if [ ! -d $src_plugins_dir ]; then
  echo "no plugins to install"
  exit 0
fi

# Get Elasticsearch version to find the correct plugin directory
ES_VERSION=$(cat /usr/share/elasticsearch/config/elasticsearch.yml 2>/dev/null | grep -o 'serviceVersion:[[:space:]]*[0-9]*\.[0-9]*\.[0-9]*' | awk '{print $2}' || echo "8.8.2")
ES_MAJOR_VERSION=$(echo $ES_VERSION | cut -d'.' -f1)
ES_FULL_VERSION=$ES_VERSION

function native_install_plugin() {
  plugin=$1
  msg=`/usr/share/elasticsearch/bin/elasticsearch-plugin install -b $plugin`
  if [ $? == 0 ]; then
    echo "successfully installed plugin $plugin"
  else
    echo $msg | grep 'already exists'
    if [ $? == 0 ]; then
      echo "plugin $plugin already exists"
    else
      echo "failed to install plugin $plugin"
      exit 1
    fi
  fi
}

function copy_install_plugin() {
   plugin=$1
   if [ -d $dst_plugins_dir/$plugin ]; then
        echo "plugin $plugin already exists"
        return
   fi
   cp -r $plugin $dst_plugins_dir
   echo "successfully installed plugin $plugin"
}

# Install version-specific plugins - simply install all plugins that exist for this version
echo "Installing plugins for Elasticsearch version $ES_FULL_VERSION"

# Check if version-specific plugin directory exists
if [ -d "$src_plugins_dir/$ES_FULL_VERSION" ]; then
    echo "Found plugin directory for version $ES_FULL_VERSION"

    # Install all plugin subdirectories that exist
    for plugin_dir in "$src_plugins_dir/$ES_FULL_VERSION"/*/; do
        if [ -d "$plugin_dir" ]; then
            plugin_name=$(basename "$plugin_dir")
            echo "Installing $plugin_name plugin for version $ES_FULL_VERSION"
            copy_install_plugin "$plugin_dir"
        fi
    done
else
    echo "No plugin directory found for version $ES_FULL_VERSION"
fi
