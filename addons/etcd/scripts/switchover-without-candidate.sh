#!/bin/bash

set -exo pipefail

leader_endpoints=${KB_CONSENSUS_LEADER_POD_FQDN}:2379
leader_id=$(etcdctl --endpoints=$leader_endpoints endpoint status | awk -F', ' '{print $2}')

member_ids=$(etcdctl --endpoints=$leader_endpoints member list | awk -F', ' '{print $1}')
random_candidate_id=$(echo "$member_ids" | grep -v "$leader_id" | awk 'NR==1')

if [ -z "$random_candidate_id" ]; then
  echo "no candidate found"
  exit 1
fi

etcdctl --endpoints=$leader_endpoints move-leader $random_candidate_id

status=$(etcdctl --endpoints=$leader_endpoints endpoint status)
is_leader=$(echo $status | awk -F ', ' '{print $5}')

if [ "false" == $is_leader ]; then
  echo "switchover successfully"
else
  echo "switchover failed, please check!"
  exit 1
fi