#!/bin/bash

set -ex

start_bookkeeper() {
  bin/apply-config-from-env.py conf/bookkeeper.conf
  exec bin/bookkeeper autorecovery
}

# main
start_bookkeeper