#!/bin/sh

tlsDir=$TLS_DIR
status=$(execEtcdctl 127.0.0.1:2379 endpoint status --command-timeout=300ms --dial-timeout=100m)
IsLeader=$(echo $status | awk -F ', ' '{print $5}')
IsLearner=$(echo $status | awk -F ', ' '{print $6}')

if [ "true" = "$IsLeader" ]; then
  echo -n "leader"
elif [ "true" = "$IsLearner" ]; then
  echo -n "learner"
elif [ "false" = "$IsLeader" ] && [ "false" = "$IsLearner" ]; then
  echo -n "follower"
else
  echo -n "bad role, please check!"
  exit 1
fi