#!/bin/bash
set -e

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# use the current scrip name while putting log
script_name=${0##*/}

# pid stores the process id of the proxysql process
declare -i pid

if [ $FRONTEND_TLS_ENABLED == "true" ]; then
    cp /var/lib/frontend/server/ca.crt /var/lib/proxysql/proxysql-ca.pem
    cp /var/lib/frontend/server/tls.crt /var/lib/proxysql/proxysql-cert.pem
    cp /var/lib/frontend/server/tls.key /var/lib/proxysql/proxysql-key.pem
fi

function gen_mysql_servers {
  IFS=',' read -r -a MYSQL_FQDNS_ARRAY <<< "$MYSQL_FQDNS"
  result=""

  for fqdn in "${MYSQL_FQDNS_ARRAY[@]}"; do
    index=$(echo "$fqdn" | grep -oP '\d+(?=\.)')
    HOSTGROUP_ID=3
    if [ "$index" -eq 0 ]; then
      HOSTGROUP_ID=2
    fi
    config="  { hostgroup_id = $HOSTGROUP_ID , hostname = \"$fqdn\", port = 3306, weight = 1, use_ssl = 0 }"
    if [ -z "$result" ]; then
      result="$config"
    else
      result="$result, \n$config"
    fi
  done

  echo "$result"
}

# If command has arguments, prepend proxysql
if [ "${1:0:1}" = '-' ]; then
    CMDARG="$@"
fi

# if test by shellspec include, just return 0
if [ "${__SOURCED__:+x}" ]; then
  return 0
fi

function replace_config_variables() {
  mysql_servers=$(gen_mysql_servers)
  awk -v mysql_servers="$mysql_servers" '{gsub(/\${MYSQL_SERVERS}/, mysql_servers); print}' /config/custom-config/proxysql.tpl > /proxysql.cnf

  sed -i "s|\${PROXYSQL_MONITOR_PASSWORD}|${PROXYSQL_MONITOR_PASSWORD}|g" /proxysql.cnf
  sed -i "s|\${PROXYSQL_CLUSTER_PASSWORD}|${PROXYSQL_CLUSTER_PASSWORD}|g" /proxysql.cnf
  sed -i "s|\${PROXYSQL_ADMIN_PASSWORD}|${PROXYSQL_ADMIN_PASSWORD}|g" /proxysql.cnf
}

echo "Configuring proxysql ..."
replace_config_variables
# Start ProxySQL with PID 1
exec proxysql -c /proxysql.cnf -f $CMDARG &
pid=$!

/scripts/proxysql/configure-proxysql.sh

echo "Waiting for proxysql ..."
wait $pid

