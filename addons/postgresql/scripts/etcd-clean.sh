#!/bin/bash
if [ -z "$ETCD_SERVER" ]; then
  exit 0
fi

echo "Find command kubectl"
if command -v kubectl &> /dev/null; then
  IFS=',' read -ra POD_NAMES <<< "$KB_CLUSTER_POD_NAME_LIST"

  for POD_NAME in "${POD_NAMES[@]}"; do
    echo "Attempting to execute pkill -f /usr/local/bin/patroni in pod: $POD_NAME"

    MAX_ATTEMPTS=3
    ATTEMPT=1
    SUCCESS=0
    
    while [ "$ATTEMPT" -le "$MAX_ATTEMPTS" ]; do
      echo "Attempt $ATTEMPT: Executing pkill -f /usr/local/bin/patroni in pod: $POD_NAME"
      kubectl exec $POD_NAME -- pkill -f /usr/local/bin/patroni

      # Check if the process was successfully killed
      sleep 2  # Wait for a moment to allow the process to terminate
      REMAINING_COUNT=$(kubectl exec $POD_NAME -- pgrep -c -f /usr/local/bin/patroni)

      if [ "$REMAINING_COUNT" -eq 0 ]; then
        echo "Successfully killed /usr/local/bin/patroni process in pod: $POD_NAME on attempt $ATTEMPT"
        SUCCESS=1
        break
      else
        echo "Failed to kill /usr/local/bin/patroni process in pod: $POD_NAME, attempt $ATTEMPT, remaining count: $REMAINING_COUNT"
      fi

      ATTEMPT=$((ATTEMPT + 1))
    done

    # Check if all attempts failed
    if [ "$SUCCESS" -eq 0 ]; then
      echo "Error: Failed to kill /usr/local/bin/patroni process in pod: $POD_NAME after $MAX_ATTEMPTS attempts. Exiting."
      exit 1
    fi
  done
else
  echo "kubectl not found, please ensure it is installed and accessible"
  exit 1
fi

export ETCDCTL_API=${ETCD_API:-'3'}

endpoints=${ETCD_SERVER:-'127.0.0.1:2379'}

servers=""
IFS=',' read -ra ADDR <<< "$endpoints"
for addr in "${ADDR[@]}"; do
  if [[ $addr != http* ]]; then
    addr="http://$addr"
  fi
  servers="${servers},${addr}"
done

servers=${servers:1}

echo $servers

echo "Deleting all keys with prefix /service/${KB_CLUSTER_NAME}-${KB_COMP_NAME}-patroni${KB_CLUSTER_UID_POSTFIX_8} from Etcd server at ${endpoints}..."

if [[ ${ETCDCTL_API} == "2" ]]; then
  etcdctl --endpoints $servers rm -r /service/${KB_CLUSTER_NAME}-${KB_COMP_NAME}-patroni${KB_CLUSTER_UID_POSTFIX_8}
else 
  etcdctl --endpoints $servers del /service/${KB_CLUSTER_NAME}-${KB_COMP_NAME}-patroni${KB_CLUSTER_UID_POSTFIX_8} --prefix
fi

if [ $? -eq 0 ]; then
    echo "Successfully deleted all keys with prefix /service/${KB_CLUSTER_NAME}-${KB_COMP_NAME}-patroni${KB_CLUSTER_UID_POSTFIX_8}."
else
    echo "Failed to delete keys. Please check your Etcd server and try again."
    exit 0
fi