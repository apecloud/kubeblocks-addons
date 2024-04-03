#!/bin/bash
set -o errexit
set -o nounset



chown -R halo:halo /data/halo
chmod 0750 /data/halo


gosu halo bash -c 'patroni /halo-scripts/patroni.yml'
