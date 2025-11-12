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
. /opt/scripts/hbase/env.sh

print_welcome_page

if [[ $DEBUG_MODEL == true ]]; then
  info ************** env-start **************
  env
  info ************** env-end **************
fi

bash /hbase/scripts/hbase-config-setup.sh

if [[ "$*" = *"/opt/scripts/hbase/run.sh"* || "$*" = *"/run.sh"* ]]; then
    info "** HRegionServer setup **"
    /opt/scripts/hbase/post-start.sh
    info "** HRegionServer setup finished! **"
fi

START_COMMAND=("${HBASE_HOME}/bin/hbase-daemon.sh" "foreground_start" "regionserver" "$@")

if am_i_root; then
  info "** Starting HRegionServer **"
  exec_as_user "$HBASE_DAEMON_USER" "${START_COMMAND[@]}"
else
  info "** Starting HRegionServer **"
  #${HBASE_HOME}/bin/hbase-daemon.sh start regionserver
  exec "${START_COMMAND[@]}"
fi
