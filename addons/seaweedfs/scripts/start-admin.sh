#!/bin/sh
set -eu
# shellcheck source=addons/seaweedfs/scripts/common.sh
. "$(dirname "$0")/common.sh"
masters=$(seaweedfs_endpoints "${SEAWEEDFS_MASTER_FQDNS:-}" 9333)
data_dir=${SEAWEEDFS_DATA_DIR:-/data/admin}
mkdir -p "$data_dir"
exec weed -logtostderr=true admin -ip=0.0.0.0 -allowInsecureBind \
  -port=23646 -port.grpc=33646 -master="$masters" -dataDir="$data_dir"
