#!/bin/sh
set -eu
# shellcheck source=addons/seaweedfs/scripts/common.sh
. "$(dirname "$0")/common.sh"
self=$(seaweedfs_self)
peers=$(seaweedfs_endpoints "${SEAWEEDFS_POD_FQDNS:-}" 9333)
case "${SEAWEEDFS_MASTER_REPLICAS:-}" in
  1) case "$peers" in *,*) seaweedfs_fail 'single master requires exactly one peer' ;; esac; peers=none ;;
  3) peer_count=$(printf '%s' "$peers" | awk -F, '{print NF}')
     [ "$peer_count" = 3 ] || seaweedfs_fail 'distributed master requires exactly three peers' ;;
  *) seaweedfs_fail 'master replicas must be fixed at 1 or 3' ;;
esac
case "${SEAWEEDFS_REPLICATION:-}" in 000|001) ;; *) seaweedfs_fail 'unsupported replication placement' ;; esac
case "${SEAWEEDFS_VOLUME_SIZE_MB:-}" in ''|*[!0-9]*) seaweedfs_fail 'volume size must be a positive integer' ;; esac
[ "$SEAWEEDFS_VOLUME_SIZE_MB" -gt 0 ] || seaweedfs_fail 'volume size must be positive'
data_dir=${SEAWEEDFS_DATA_DIR:-/data/master}
mkdir -p "$data_dir"
exec weed -logtostderr=true master -ip="$self" -ip.bind=0.0.0.0 -metricsPort=9327 \
  -port=9333 -port.grpc=19333 -mdir="$data_dir" -peers="$peers" \
  -defaultReplication="$SEAWEEDFS_REPLICATION" \
  -volumeSizeLimitMB="$SEAWEEDFS_VOLUME_SIZE_MB" -telemetry=false
