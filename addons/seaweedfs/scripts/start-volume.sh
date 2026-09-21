#!/bin/sh
set -eu
# shellcheck source=addons/seaweedfs/scripts/common.sh
. "$(dirname "$0")/common.sh"
self=$(seaweedfs_self)
masters=$(seaweedfs_endpoints "${SEAWEEDFS_MASTER_FQDNS:-}" 9333)
data_dir=${SEAWEEDFS_DATA_DIR:-/data/volume}
mkdir -p "$data_dir"
exec weed -logtostderr=true volume -ip="$self" -ip.bind=0.0.0.0 -metricsPort=9327 \
  -port=8080 -port.grpc=18080 -dir="$data_dir" -master="$masters" \
  -max=0 -index=leveldb -dataCenter=default -rack=default
