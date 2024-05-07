#!/bin/bash

set -e

export ZOOKEEPER_SERVERS=${KB_POD_LIST}

bin/apply-config-from-env.py conf/zookeeper.conf;
bin/generate-zookeeper-config.sh conf/zookeeper.conf; exec bin/pulsar zookeeper;
