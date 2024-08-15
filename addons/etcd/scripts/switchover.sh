#!/bin/sh

set -ex
leaderEndpoint=${KB_LEADER_POD_FQDN}.${KB_NAMESPACE}.svc${CLUSTER_DOMAIN}:2379
oldLeaderEndpoint=$leaderEndpoint

leaderChanged="false"
candidateEndpoint=""
if [ -n "$KB_SWITCHOVER_CANDIDATE_FQDN" ]; then
  candidateEndpoint=${KB_SWITCHOVER_CANDIDATE_FQDN}.${KB_NAMESPACE}.svc${CLUSTER_DOMAIN}:2379
fi

# see common.sh, this function may change leaderEndpoint
updateLeaderIfNeeded 3

if [ "$oldLeaderEndpoint" != "$leaderEndpoint" ]; then
  echo "leader already changed"
  leaderChanged="true"
fi

# leader no changed and candidate undefined
if [ "$leaderChanged" = "false" ] && [ -z "$candidateEndpoint" ]; then
  leaderID=$(execEtcdctl ${leaderEndpoint} endpoint status | awk -F', ' '{print $2}')
  peerIDs=$(execEtcdctl ${leaderEndpoint} member list | awk -F', ' '{print $1}')
  randomCandidateID=$(echo "$peerIDs" | grep -v "$leaderID" | awk 'NR==1')
  if [ -z "$randomCandidateID" ]; then
    echo "no candidate found"
    exit 1
  fi
  execEtcdctl $leaderEndpoint move-leader $randomCandidateID

# leader changed and candidate undefined
elif [ "$leaderChanged" = "true" ] && [ -z "$candidateEndpoint" ]; then
  echo "leader already changed, no need to switch"
  exit 0

# candidate defined, directly switch leader to candidate
elif [ "$leaderChanged" = "false" ] && [ -n "$candidateEndpoint" ]; then
  if [ "$leaderEndpoint" = "$candidateEndpoint" ]; then
    echo "leader is the same as candidate, no need to switch"
    exit 0
  fi
  candidateID=$(execEtcdctl ${candidateEndpoint} endpoint status | awk -F', ' '{print $2}')
  execEtcdctl $leaderEndpoint move-leader $candidateID
fi

# after switchover, do a verification
status=$(execEtcdctl $leaderEndpoint endpoint status)
isLeader=$(echo $status | awk -F ', ' '{print $5}')

if [ "$isLeader" = "false" ]; then
  echo "switchover successfully"
else
  echo "switchover failed, please check!"
  exit 1
fi