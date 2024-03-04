#!/bin/bash
#

set -x
# do switchover
echo "INFO: doing switchover.."
echo "INFO: candidate: ${candidate}"
kubectl exec -it mc-mogdb-1 -c mogdb -- gosu omm gs_ctl switchover

# check if switchover successfully.
echo "INFO: start to check if switchover successfully, timeout is 60s"
executedUnix=$(date +%s)
while true; do
  sleep 5
  if [ ! -z ${candidate} ]; then
     # if candidate specified, only check it
     role=$(kubectl get pod ${candidate} -ojson | jq -r '.metadata.labels["kubeblocks.io/role"]')
     if [ "$role" == "primary" ] || [ "$role" == "leader" ] || [ "$role" == "master" ]; then
        echo "INFO: switchover successfully, ${candidate} is ${role}"
        exit 0
     fi
  else
    # check if the candidate instance has been promote to primary
    pods=$(kubectl get pod -l apps.kubeblocks.io/component-name=${KB_COMP_NAME},app.kubernetes.io/instance=${KB_CLUSTER_NAME} | awk 'NR > 1 {print $1}')
    for podName in ${pods}; do
       if [ "${podName}" != "${primary}" ];then
         role=$(kubectl get pod ${podName} -ojson | jq -r '.metadata.labels["kubeblocks.io/role"]')
         if [ "$role" == "primary" ] || [ "$role" == "leader" ] || [ "$role" == "master" ]; then
            echo "INFO: switchover successfully, ${podName} is ${role}"
            exit 0
         fi
       fi
    done
  fi
  currentUnix=$(date +%s)
  diff_time=$((${currentUnix}-${executedUnix}))
  if [ ${diff_time} -ge 60 ]; then
    echo "ERROR: switchover failed."
    exit 1
  fi
done