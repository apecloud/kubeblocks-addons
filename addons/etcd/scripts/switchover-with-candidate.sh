#!/bin/bash

set -exo pipefail

leader_endpoints=${KB_CONSENSUS_LEADER_POD_FQDN}:2379
candidate_endpoints=${KB_SWITCHOVER_CANDIDATE_FQDN}:2379

candidateID=$(etcdctl --endpoints=$candidate_endpoints endpoint status | awk -F', ' '{print $2}')
etcdctl --endpoints=$leader_endpoints move-leader $candidateID

status=$(etcdctl --endpoints=$leader_endpoints endpoint status)
is_leader=$(echo $status | awk -F ', ' '{print $5}')

if [ "false" == "$is_leader" ]; then
  echo "switchover successfully"
else
  echo "switchover failed, please check!"
  exit 1
fi