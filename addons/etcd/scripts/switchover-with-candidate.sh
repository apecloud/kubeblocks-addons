#!/bin/sh

set -ex
leaderEndpoint=${KB_LEADER_POD_FQDN}.${KB_NAMESPACE}.svc${CLUSTER_DOMAIN}:2379
candidateEndpoint=${KB_SWITCHOVER_CANDIDATE_FQDN}.${KB_NAMESPACE}.svc${CLUSTER_DOMAIN}:2379

# see common.sh, this function may change leaderEndpoint
updateLeaderIfNeeded 3

if [ "$leaderEndpoint" = "$candidateEndpoint" ]; then
  echo "leader is the same as candidate, no need to switch"
  exit 0
fi

candidateID=$(execEtcdctlNoCheckTLS ${candidateEndpoint} endpoint status | awk -F', ' '{print $2}')
execEtcdctlNoCheckTLS ${leaderEndpoint} move-leader $candidateID

status=$(execEtcdctlNoCheckTLS ${candidateEndpoint} endpoint status)
isLeader=$(echo ${status} | awk -F ', ' '{print $5}')

if [ "$isLeader" = "true" ]; then
  echo "switchover successfully"
else
  echo "switchover failed, please check!"
  exit 1
fi