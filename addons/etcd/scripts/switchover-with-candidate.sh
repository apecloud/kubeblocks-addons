#!/bin/bash

set -exo pipefail

leaderEndpoints=${KB_CONSENSUS_LEADER_POD_FQDN}:2379
candidateEndpoints=${KB_SWITCHOVER_CANDIDATE_FQDN}:2379

candidateID=$(execEtcdctl $candidateEndpoints endpoint status | awk -F', ' '{print $2}')
execEtcdctl $leaderEndpoints move-leader $candidateID

status=$(execEtcdctl $leaderEndpoints endpoint status)
isLeader=$(echo $status | awk -F ', ' '{print $5}')

if [ $isLeader = "false" ]; then
  echo "switchover successfully"
else
  echo "switchover failed, please check!"
  exit 1
fi