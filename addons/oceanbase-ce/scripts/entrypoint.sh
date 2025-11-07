#!/usr/bin/env bash

#
# Copyright (c) 2023 OceanBase
# ob-operator is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#          http://license.coscl.org.cn/MulanPSL2
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
# See the Mulan PSL v2 for more details.
#
source /scripts/bootstrap.sh

RECOVERING="$(is_recovering)"
echo "Recovering: $RECOVERING"

adjust_ob_cluster_ip_feat

if [ $RECOVERING = "True" ]; then
  if [ "$(check_if_ip_changed)" = "Changed" ]; then
    echo "IP changed, failed to rejoin the cluster"
    exit 1
  fi
  start_observer_with_exsting_configs
  wait_for_observer_ready
  create_ready_flag
  echo "Check DB Status"
  wait_for_observer_active
else
  echo "New machine, need to join the cluster"
  echo "Prepare config folders"
  prepare_dirs
  echo "Start server"
  start_observer
  wait_for_observer_ready
  echo "Creating readiness flag..."
  create_ready_flag
  # If current server is chosen to run RS
  if [ $ORDINAL_INDEX -lt $ZONE_COUNT ]; then
    # Choose the first RS to bootstrap
    if [ $ORDINAL_INDEX -eq 0 ]; then
      echo "Choose the first RS to bootstrap cluster"
      echo "Wait for all Rootservice to be ready"
      bootstrap_obcluster
      if [ $? -eq 0 ]; then
        echo "Bootstrap successfully"
      fi
    else
      echo "Ready to be bootstrapped"
    fi
  else
    echo "Add this server to cluster"
    add_server
  fi
fi

echo "Cluster starts successfully"

wait_for_observer_to_term