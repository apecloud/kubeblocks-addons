# config file used to bootstrap the etcd cluster
configFile=$TMP_CONFIG_PATH

function checkBackupFile() {
  local back_file=$1
  output=$(etcdutl --endpoints=$ENDPOINTS --write-out=table snapshot status ${back_file})
  # Check if the command was successful
  if [ $? -ne 0 ]; then
    echo "ERROR: Failed to check the backup file with etcdutl"
    exit 1
  fi
  # Extract the total key from the output
  totalKey=$(echo "${output}" | awk '/TOTAL KEYS/ {getline; getline; print;}' | awk '{print $6}')
  # Check if total key is a number
  if ! [[ $totalKey =~ ^[0-9]+$ ]]; then
    echo "ERROR: The value of 'totalKey' is not a valid number."
    exit 1
  fi
  # Check if total key is too small
  if [ "$totalKey" -le 8 ]; then
    echo "WARNING: The value of 'totalKey' is less or equal the 8(initial number of 3 etcd cluster)."
    exit 1
  fi
}

function getClientProtocol() {
  # check client tls if is enabled
  line=$(grep 'advertise-client-urls' ${configFile})
  if echo $line | grep -q 'https'; then
    echo "https"
  elif echo $line | grep -q 'http'; then
    echo "http"
  fi
}

function getPeerProtocol() {
  # check peer tls if is enabled
  line=$(grep 'initial-advertise-peer-urls' ${configFile})
  if echo $line | grep -q 'https'; then
    echo "https"
  elif echo $line | grep -q 'http'; then
    echo "http"
  fi
}

function execEtcdctl() {
  local endpoints=$1
  clientProtocol=$(getClientProtocol)
  tlsDir=$TLS_DIR
  # Check if the clientProtocol is https and the tlsDir is not empty
  if [ $clientProtocol = "https" ] && [ -d "$tlsDir" ] && [ -s "${tlsDir}/ca.crt" ] && [ -s "${tlsDir}/tls.crt" ] && [ -s "${tlsDir}/tls.key" ]; then
    etcdctl --endpoints=${endpoints} --cacert=${tlsDir}/ca.crt --cert=${tlsDir}/tls.crt --key=${tlsDir}/tls.key "${@:2}"
  elif [ $clientProtocol = "http" ]; then
    etcdctl --endpoints=${endpoints} "${@:2}"
  else
    echo "ERROR: bad etcdctl args: clientProtocol:${clientProtocol}, endpoints:${endpoints}, tlsDir:${tlsDir}, please check!"
    exit 1
  fi
  # Check if the etcdctl command was successful
  if [ $? -eq 0 ]; then
    echo "etcdctl command was successful"
  else
    echo "etcdctl command failed"
    exit 1
  fi
}
