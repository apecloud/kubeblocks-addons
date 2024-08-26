#!/bin/sh

switchoverWithCandidate() {
  leaderEndpoint=${LEADER_POD_FQDN}:2379
  candidateEndpoint=${KB_SWITCHOVER_CANDIDATE_FQDN}:2379
  
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
}

switchoverWithoutCandidate() {
  leaderEndpoint=${LEADER_POD_FQDN}:2379
  oldLeaderEndpoint=$leaderEndpoint
  
  # see common.sh, this function may change leaderEndpoint
  updateLeaderIfNeeded 3
  
  if [ "$oldLeaderEndpoint" != "$leaderEndpoint" ]; then
    echo "leader already changed, no need to switch"
    exit 0
  fi
  
  leaderID=$(execEtcdctlNoCheckTLS ${leaderEndpoint} endpoint status | awk -F', ' '{print $2}')
  peerIDs=$(execEtcdctlNoCheckTLS ${leaderEndpoint} member list | awk -F', ' '{print $1}')
  randomCandidateID=$(echo "$peerIDs" | grep -v "$leaderID" | awk 'NR==1')
  
  if [ -z "$randomCandidateID" ]; then
    echo "no candidate found"
    exit 1
  fi
  
  execEtcdctlNoCheckTLS $leaderEndpoint move-leader $randomCandidateID
  
  status=$(execEtcdctlNoCheckTLS $leaderEndpoint endpoint status)
  isLeader=$(echo $status | awk -F ', ' '{print $5}')
  
  if [ "$isLeader" = "false" ]; then
    echo "switchover successfully"
  else
    echo "switchover failed, please check!"
    exit 1
  fi
}
