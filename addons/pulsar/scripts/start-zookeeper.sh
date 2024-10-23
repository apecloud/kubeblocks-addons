#!/bin/bash

set -ex

start_zookeeper() {
  export ZOOKEEPER_SERVERS=${ZK_POD_NAME_LIST}
  bin/apply-config-from-env.py conf/zookeeper.conf;
  bin/generate-zookeeper-config.sh conf/zookeeper.conf; exec bin/pulsar zookeeper;
}

# main
start_zookeeper
