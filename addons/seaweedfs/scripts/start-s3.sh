#!/bin/sh
set -eu
# shellcheck source=addons/seaweedfs/scripts/common.sh
. "$(dirname "$0")/common.sh"
[ -n "${AWS_ACCESS_KEY_ID:-}" ] || seaweedfs_fail 'S3 access key is required'
[ -n "${AWS_SECRET_ACCESS_KEY:-}" ] || seaweedfs_fail 'S3 secret key is required'
[ -n "${SEAWEEDFS_FILER_HOST:-}" ] || seaweedfs_fail 'filer service is required'
[ -n "${SEAWEEDFS_FILER_PORT:-}" ] || seaweedfs_fail 'filer port is required'
# Credentials are read by the engine from the environment, never placed in argv.
# Disable the unrelated Iceberg and Lance listeners enabled by default in 4.47.
exec weed -logtostderr=true s3 -ip.bind=0.0.0.0 -port=8333 \
  -filer="${SEAWEEDFS_FILER_HOST}:${SEAWEEDFS_FILER_PORT}" \
  -port.iceberg=0 -port.lance=0
