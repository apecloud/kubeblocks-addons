#!/bin/sh

# config file used to bootstrap the etcd cluster
configFile=$TMP_CONFIG_PATH

checkBackupFile() {
  local backupFile=$1
  output=$(etcdutl snapshot status ${backupFile})
  # check if the command was successful
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to check the backup file with etcdutl"
    exit 1
  fi
  # extract the total key from the output
  totalKey=$(echo $output | awk -F', ' '{print $3}')
  # check if total key is a number
  case $totalKey in
    *[!0-9]*)
      echo "ERROR: snapshot totalKey is not a valid number."
      exit 1
      ;;
  esac

  # define a threshold to check if the total key count is too low
  # consider increasing this value when dealing with production-grade etcd cluster
  threshold=$BACKUP_KEY_THRESHOLD #[modifiable]
  if [ "$totalKey" -lt $threshold ]; then
    echo "WARNING: snapshot totalKey is less than the threshold"
    exit 1
  fi
}

getClientProtocol() {
  # check client tls if is enabled
  line=$(grep 'advertise-client-urls' ${configFile})
  if echo $line | grep -q 'https'; then
    echo "https"
  elif echo $line | grep -q 'http'; then
    echo "http"
  fi
}

getPeerProtocol() {
  # check peer tls if is enabled
  line=$(grep 'initial-advertise-peer-urls' ${configFile})
  if echo $line | grep -q 'https'; then
    echo "https"
  elif echo $line | grep -q 'http'; then
    echo "http"
  fi
}

execEtcdctl() {
  local endpoints=$1
  shift
  clientProtocol=$(getClientProtocol)
  tlsDir=$TLS_MOUNT_PATH
  # check if the clientProtocol is https and the tlsDir is not empty
  if [ $clientProtocol = "https" ] && [ -d "$tlsDir" ] && [ -s "${tlsDir}/ca.crt" ] && [ -s "${tlsDir}/tls.crt" ] && [ -s "${tlsDir}/tls.key" ]; then
    etcdctl --endpoints=${endpoints} --cacert=${tlsDir}/ca.crt --cert=${tlsDir}/tls.crt --key=${tlsDir}/tls.key "$@"
  elif [ $clientProtocol = "http" ]; then
    etcdctl --endpoints=${endpoints} "$@"
  else
    echo "ERROR: bad etcdctl args: clientProtocol:${clientProtocol}, endpoints:${endpoints}, tlsDir:${tlsDir}, please check!"
    exit 1
  fi
  # check if the etcdctl command was successful
  if [ $? -ne 0 ]; then
    echo "etcdctl command failed"
    exit 1
  fi
}

# this function will be deprecated in the future
execEtcdctlNoCheckTLS() {
  local endpoints=$1
  shift
  etcdctl --endpoints=${endpoints} "$@"
  # check if the etcdctl command was successful
  if [ $? -ne 0 ]; then
    echo "etcdctl command failed"
    exit 1
  fi
}

updateLeaderIfNeeded() {
  local retries=$1

  if [ $retries -le 0 ]; then
    echo "Maximum number of retries reached, leader is not ready"
    exit 1
  fi

  status=$(execEtcdctlNoCheckTLS ${leaderEndpoint} endpoint status)
  isLeader=$(echo $status | awk -F ', ' '{print $5}')
  if [ $isLeader = "false" ]; then
    echo "leader out of status, try to redirect to new leader"
    peerEndpoints=$(execEtcdctlNoCheckTLS "$leaderEndpoint" member list | awk -F', ' '{print $5}' | tr '\n' ',' | sed 's#,$##')
    leaderEndpoint=$(execEtcdctlNoCheckTLS "$peerEndpoints" endpoint status | awk -F', ' '$5=="true" {print $1}')
    if [ $leaderEndpoint = "" ]; then
      echo "leader is not ready, wait for 2s..."
      sleep 2
      updateLeaderIfNeeded $(expr $retries - 1)
    fi
  fi

  if [ $leaderEndpoint = $candidateEndpoint ]; then
    echo "leader is the same as candidate, no need to switch"
    exit 0
  fi
}