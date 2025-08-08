#!/usr/bin/env bash

set -o errexit

src_plugins_dir=/tmp/plugins
dst_plugins_dir=/usr/share/elasticsearch/plugins

if [ ! -d $src_plugins_dir ]; then
  echo "no plugins to install"
  exit 0
fi

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

for plugin in $(ls $src_plugins_dir); do
    # check if plugin has suffix .zip or .gz or .tar.gz
    echo "installing plugin $plugin"
    if [[ $plugin == *.zip || $plugin == *.gz || $plugin == *.tar.gz ]]; then
        native_install_plugins $src_plugins_dir/$plugin
    else
        copy_install_plugin $src_plugins_dir/$plugin
    fi
done
