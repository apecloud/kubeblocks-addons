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
. /hbase/scripts/common.sh

if [[ "$*" = *"/opt/scripts/hbase/run.sh"* || "$*" = *"/run.sh"* ]]; then
    info "** Thrift setup **"
    /opt/scripts/hbase/post-start.sh
    info "** Thrift setup finished! **"
fi


START_COMMAND=("${HBASE_HOME}/bin/hbase-daemon.sh" "foreground_start" "thrift" "$@")

tail_logs "thrift" &
if am_i_root; then
  info "** Starting Thrift **"
  exec_as_user "$HBASE_DAEMON_USER" "${START_COMMAND[@]}"
else
  info "** Starting Thrift **"
  exec "${START_COMMAND[@]}"
fi