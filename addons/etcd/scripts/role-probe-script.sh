tlsDir=$TLS_DIR
status=""

if [ -d $tlsDir ]; then
  status=$(etcdctl --endpoints=127.0.0.1:2379 --cacert=${tlsDir}/ca.crt --cert=${tlsDir}/tls.crt --key=${tlsDir}/tls.key endpoint status -w simple --command-timeout=300ms --dial-timeout=100m)
else
  status=$(etcdctl --endpoints=127.0.0.1:2379 endpoint status -w simple --command-timeout=300ms --dial-timeout=100m)
fi

IsLeader=$(echo $status | awk -F ', ' '{print $5}')
IsLearner=$(echo $status | awk -F ', ' '{print $6}')

if [ "true" = "$IsLeader" ]; then
  echo -n "leader";
elif [ "true" = "$IsLearner" ]; then
  echo -n "learner"
else
  echo -n "follower"
fi