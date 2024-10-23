#!/bin/bash

set -ex

start_proxy() {
  python3 /kb-scripts/merge_pulsar_config.py conf/proxy.conf /opt/pulsar/conf/proxy.conf &&
  bin/apply-config-from-env.py conf/proxy.conf && echo 'OK' > status && exec bin/pulsar proxy
}

# main
start_proxy