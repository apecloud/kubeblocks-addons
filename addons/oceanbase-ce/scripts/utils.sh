
#!/usr/bin/env bash

function get_pod_ip {
  pod_name=${1:?missing pod name}
  if [ "$OB_USE_CLUSTER_IP" = "enabled" ]; then
    # get suffix of pod name
    pod_ordinal=$(echo $pod_name | awk -F '-' '{print $(NF)}')
    # parse service name
    replica_hostname=${KB_CLUSTER_COMP_NAME}-ordinal-${pod_ordinal}
  else
    replica_hostname=${pod_name}.${SUBDOMAIN}
  fi
  get_pod_ip_by_hostname $replica_hostname
}

function get_pod_ip_by_hostname {
  while true; do
    replica_ip=$(nslookup $replica_hostname | tail -n 2 | grep -P "(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})" --only-matching)
    if [ $? -ne 0 ]; then
      sleep 5
    else
      echo $replica_ip
      break
    fi
  done
}

function get_ob_major_version {
  version=$(/home/admin/oceanbase/bin/observer --version 2>&1  | grep -oP '(\d+\.\d+\.\d+)')
  echo $version
}

function get_ob_full_version {
  version=$(/home/admin/oceanbase/bin/observer --version 2>&1  | grep -oP '(\d+\.\d+\.\d+\.\d+)')
  echo $version
}

function version_gt() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; }
function version_le() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" == "$1"; }
function version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }
function version_ge() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"; }
function version_eq() {
  version_ge $1 $2
  ret1=$?
  version_le $1 $2
  ret2=$?
  return $(($ret1 || $ret2))
}


function wait_for_observer_to_term {
# wait for observer to exit
  while true; do
    if [ -z "$(pidof observer)" ]; then
      exit 1
    fi
    sleep 5
  done
}