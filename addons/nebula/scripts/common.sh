root_dir=/usr/local/nebula
logs_dir=${root_dir}/logs

function tail_logs() {
  local svc_name=$1
  while true; do
    sleep 1
    if [[ -f ${logs_dir}/nebula-${svc_name}.INFO || -f ${logs_dir}/nebula-${svc_name}.WARNING || -f ${logs_dir}/nebula-${svc_name}.ERROR ]] ; then
      break
    fi
  done
  tail -F ${logs_dir}/nebula-${svc_name}.{INFO,WARNING,ERROR}
}


function check_service_is_stopped() {
  while true; do
    sleep 1
    pid=`ps -eo pid,args | grep -F "${root_dir}/bin/nebula-${1}" | grep -v "grep" | tail -1 | awk '{print $1}'`
    if [ -z "$pid" ]; then
      echo "$(date): ${1} is stopped."
      break
    fi
  done
}


function kill_agent() {
  pid=`ps -eo pid,args | grep -F "/usr/local/nebula/console/agent" | grep -v "grep" | tail -1 | awk '{print $1}'`
  if [ -n "$pid" ]; then
    kill -9 $pid
  fi
}

function nebula_service_start() {
  cp ${root_dir}/config/nebula-$1.conf ${root_dir}/etc/nebula-$1.conf
  printf "\n--local_ip=${POD_FQDN}" >> ${root_dir}/etc/nebula-$1.conf
  ${root_dir}/scripts/nebula.service -c ${root_dir}/etc/nebula-$1.conf start $1
  wait_service_ready
}

function wait_service_ready() {
  count=0
  set +e
  while true; do
      if [ $count -gt 10 ]; then
          echo "Service is not ready after waiting for a long time"
          exit 1
      fi
      count=$((count+1))
      response=$(curl -s http://127.0.0.1:${HTTP_PORT}/status)
      if echo "$response" | grep "running"; then
          echo "Service is ready"
          break
      fi
      sleep 3
  done
  set -e
}

function start_nebula_agent() {
   meta_ep=$(echo $NEBULA_METAD_SVC | cut -d',' -f1 | cut -d':' -f1)
   until curl -L  http://${meta_ep}:19559/status; do sleep 5; done
   touch ${root_dir}/logs/.kb_agent
   /usr/local/nebula/console/agent  --agent="${POD_FQDN}:8888" --meta="${meta_ep}:9559" 2>&1 >> ${logs_dir}/agent.log &
}

function end_restore() {
  echo "$(date): Nebula restoration completed."
  kill_agent
  ${root_dir}/scripts/nebula.service stop $1
  check_service_is_stopped $1
  rm -f ${root_dir}/logs/.kb_agent
}

function check_agent() {
  pid=`ps -eo pid,args | grep -F "/usr/local/nebula/console/agent" | grep -v "grep" | tail -1 | awk '{print $1}'`
  if [ -z "$pid" ]; then
    echo "$(date): Nebula agent process is not running, exit..."
    exit 1
  fi
}