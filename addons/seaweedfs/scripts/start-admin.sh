#!/bin/sh
set -eu
# shellcheck source=addons/seaweedfs/scripts/common.sh
. "$(dirname "$0")/common.sh"
[ -n "${WEED_ADMIN_USER:-}" ] || seaweedfs_fail 'admin username is required'
[ -n "${WEED_ADMIN_PASSWORD:-}" ] || seaweedfs_fail 'admin password is required'
masters=$(seaweedfs_endpoints "${SEAWEEDFS_MASTER_FQDNS:-}" 9333)
data_dir="${SEAWEEDFS_DATA_DIR:-/data/admin}"
mkdir -p "$data_dir"
# Reuse the S3 account via environment variables; keep credentials out of argv.
exec weed -logtostderr=true admin -ip=0.0.0.0 -port=23646 \
  -master="$masters" -dataDir="$data_dir" -iceberg.port=0 -lance.port=0
