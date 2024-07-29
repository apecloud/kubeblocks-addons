#!/bin/bash

IP_LIST=("${KB_POD_IP}")
HOSTNAME_LIST=("${KB_CLUSTER_COMP_NAME}-0")

function check_host_ready {
  local ip=$1
  #ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 gbase@$ip exit &> /dev/null
  timeout 5 bash -c "</dev/tcp/$ip/22" 2>/dev/null
  return $?
}

function get_pod_ip_list {
  local SVC_NAME="${KB_CLUSTER_COMP_NAME}-headless.${KB_NAMESPACE}.svc"
  local wait_time=600

  for i in $(seq 1 $(($KB_REPLICA_COUNT-1))); do
    local replica_hostname="${KB_CLUSTER_COMP_NAME}-${i}"
    local replica_ip=""
    local elapsed_time=0

    echo "nslookup $replica_hostname.$SVC_NAME"
    while [ $elapsed_time -lt $wait_time ]; do
      replica_ip=$(nslookup $replica_hostname.$SVC_NAME | awk '/^Address: / { print $2 }')
      if [ -z "$replica_ip" ]; then
        echo "$replica_hostname.$SVC_NAME is not ready yet"
        sleep 10
        elapsed_time=$((elapsed_time + 10))
      else
        echo "$replica_hostname.$SVC_NAME is ready"
        echo "nslookup $replica_hostname.$SVC_NAME success, IP: $replica_ip"
        break
      fi
    done

    if [ -z "$replica_ip" ]; then
      echo "Failed to get the IP of $replica_hostname.$SVC_NAME, exiting..."
      exit 0
    fi

    IP_LIST+=("$replica_ip")
    HOSTNAME_LIST+=("$replica_hostname")
  done

  IP_LIST_COMMA=$(IFS=,; echo "${IP_LIST[*]}")
  HOSTNAME_LIST_COMMA=$(IFS=,; echo "${HOSTNAME_LIST[*]}")
  echo "get_pod_ip_list: ${IP_LIST[@]}"
  echo "hostnames: ${HOSTNAME_LIST[@]}"
}

function wait_pod_ready {
  all_pods_ready=false
  while [ "$all_pods_ready" = false ]; do
    all_pods_ready=true
    
    for ip in "${IP_LIST[@]}"; do
      if ! check_host_ready $ip; then
        echo "Pod at IP $ip SSH service is not ready."
        all_pods_ready=false
      else
        echo "Pod at IP $ip SSH service is ready."
      fi
    done
    
    if [ "$all_pods_ready" = false ]; then
      sleep 5
    fi
  done
}

echo "get pod ip list..."
get_pod_ip_list

echo "wait all pod to ready..."
wait_pod_ready

if ! sudo -u gbase -i command -v gsql &> /dev/null; then
  echo "generating cluster.xml..."
  python3 /scripts/generate_replica_xml.py "${HOSTNAME_LIST_COMMA}" "${IP_LIST_COMMA}"
  echo "YAML file has been generated and saved to /home/gbase/cluster.xml"

  echo "gs_preinstall......"

  expect << EOF
log_user 1
set timeout 1800

set mypassword [lindex \$env(GBASE_PASSWORD) 0]
spawn sudo /home/gbase/gbase_package/script/gs_preinstall -U gbase -G gbase -X /home/gbase/cluster.xml

expect {
    "(yes/no)?" {
        send "yes\r"
        exp_continue
    }
    "Password:" {
        send "\$mypassword\r"
        exp_continue
    }
    eof {
        puts "Interact completed successfully."
        wait
        exit
    }
    default {
        puts "Unexpected output: $expect_out(buffer)"
        wait
        exit
    }
}

if { [catch wait result] } {
    puts "Interact failed, process likely closed: $result"
} else {
    puts "Interact completed successfully: $result"
}
EOF
  sudo chown -R gbase:gbase /home/gbase/ # special needed
  echo "now install begin..."

  expect << EOF
log_user 1
set timeout 1800
set mypassword [lindex \$env(GBASE_PASSWORD) 0]

spawn sudo -i -u gbase /home/gbase/gbase_package/script/gs_install -X /home/gbase/cluster.xml

expect {
    "Please enter password for database:" {
        send "\$mypassword\r"
        exp_continue
    }
    "Please repeat for database:" {
        send "\$mypassword\r"
        exp_continue
    }
    eof {
        puts "Interact completed successfully."
        wait
        exit
    }
    default {
        puts "Unexpected output: $expect_out(buffer)"
        wait
        exit
    }
}

if { [catch wait result] } {
    puts "Interact failed, process likely closed: $result"
} else {
    puts "Interact completed successfully: $result"
}
EOF

  echo "install success"

  sudo -i -u gbase gs_guc reload -N all -I all -h "host all all 0.0.0.0/0 sha256"
  sudo -i -u gbase gs_guc reload -I all -c "listen_addresses='*'"
  
  sudo -i -u gbase gsql -p ${server_port} -U ${GBASE_USER} -d postgres <<EOF
ALTER USER ${GBASE_USER} PASSWORD '${GBASE_PASSWORD}';
CREATE USER ${KBADMIN_USER} WITH SYSADMIN PASSWORD '${KBADMIN_PASSWORD}';
EOF
  echo "configure success"
fi

echo "gbase cluster starting..."
sudo -i -u gbase gs_om -t start
echo "gbase cluster start success"


echo "Script execution completed."
exit 0
