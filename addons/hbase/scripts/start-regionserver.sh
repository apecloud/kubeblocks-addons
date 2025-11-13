#!/bin/bash

# shellcheck disable=SC1091

set -o errexit
set -o nounset
set -o pipefail
# set -o xtrace # Uncomment this line for debugging purposes

# Load libraries
. /opt/scripts/libs/liblog.sh
. /opt/scripts/libs/lib.sh
. /opt/scripts/libs/libos.sh

# Load HRegionServer environment variables
export HOME="/home/hadoop"
. /hbase/scripts/common.sh

if [[ "$*" = *"/opt/scripts/hbase/run.sh"* || "$*" = *"/run.sh"* ]]; then
    info "** HRegionServer setup **"
    /opt/scripts/hbase/post-start.sh
    info "** HRegionServer setup finished! **"
fi

START_COMMAND=("${HBASE_HOME}/bin/hbase-daemon.sh" "foreground_start" "regionserver" "$@")

tail_logs "regionserver" &

if am_i_root; then
  info "** Starting HRegionServer **"
  exec_as_user "$HBASE_DAEMON_USER" "${START_COMMAND[@]}"
else
  info "** Starting HRegionServer **"
  exec "${START_COMMAND[@]}"
fi
