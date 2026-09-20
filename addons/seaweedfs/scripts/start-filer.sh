#!/bin/sh
set -eu
# shellcheck source=addons/seaweedfs/scripts/common.sh
. "$(dirname "$0")/common.sh"
self=$(seaweedfs_self)
masters=$(seaweedfs_endpoints "${SEAWEEDFS_MASTER_FQDNS:-}" 9333)
data_dir=${SEAWEEDFS_DATA_DIR:-/data/filer}
mkdir -p "$data_dir"
exec weed -logtostderr=true filer -ip="$self" -ip.bind=0.0.0.0 -metricsPort=9327 \
  -port=8888 -port.grpc=18888 -master="$masters" -defaultStoreDir="$data_dir"
