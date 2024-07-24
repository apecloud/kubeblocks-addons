#!/bin/sh

set -ex

leaderEndpoint=${KB_LEADER_POD_FQDN}:2379
candidateEndpoint=${KB_SWITCHOVER_CANDIDATE_FQDN}:2379

# see common.sh, this function may change leaderEndpoint
updateLeaderIfNeeded 3

candidateID=$(execEtcdctl ${candidateEndpoint} endpoint status | awk -F', ' '{print $2}')
execEtcdctl ${leaderEndpoint} move-leader $candidateID

status=$(execEtcdctl ${candidateEndpoint} endpoint status)
isLeader=$(echo ${status} | awk -F ', ' '{print $5}')

if [ $isLeader = "false" ]; then
  echo "switchover successfully"
else
  echo "switchover failed, please check!"
  exit 1
fi