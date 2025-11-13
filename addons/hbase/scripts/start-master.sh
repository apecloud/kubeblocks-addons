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
    info "** HMaster setup **"
    /opt/scripts/hbase/post-start.sh
    info "** HMaster setup finished! **"
fi

START_COMMAND=("${HBASE_HOME}/bin/hbase-daemon.sh" "foreground_start" "master" "$@")

tail_logs "master" &
if am_i_root; then
  info "** Starting HMaster **"
  exec_as_user "$HBASE_DAEMON_USER" "${START_COMMAND[@]}"
else
  info "** Starting HMaster **"
  exec "${START_COMMAND[@]}"
fi
