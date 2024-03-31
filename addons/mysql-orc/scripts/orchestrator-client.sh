#!/bin/bash
#
# orchestrator-client: a wrapper script for calling upon orchestrator's API
#
# This script serves as a command line client for orchestrator. It talks to orchestrator
# by invoking GET requests on orchestrator's API. It formats and normalizes output, converting from
# JSON format to textual format.
#
# Command line options and output format are intentionally compatible with the CLI variation of
# orchestrator.
#
# With this script, you can conveniently talk to orchestrator without needing to have the
# orchestrator binary, configuration files, database access etc.
#
# Prerequisite:
#   set the ORCHESTRATOR_API variable to point to your orchestrator service.
#   You may specify a single endpoint, like so:
#     export ORCHESTRATOR_API="http://orchestrator.myservice.com:3000/api"
#   Or you may specify multiple endpoints, space delimited, in which case orchestrator will iterate all,
#   and require one of them to satisfy leader-check. This is your way to provide orchestrator-client
#   with all service nodes and let it figure out by itself identify of leader, no need for proxy. Example:
#     export ORCHESTRATOR_API="http://service1:3000/api http://service2:3000/api http://service3:3000/api"
#
#   Optionally set ORCHESTRATOR_INSTANCE to the local instance where mysql is running.
#   This is most likely to be used on bare metal or VM systems where you have a single
#   MySQL instance running on a known port, in which case you would ensure that
#   /etc/profile.d/orchestrator-client.sh contains code that does:
#       export ORCHESTRATOR_INSTANCE=`hostname` or
#       export ORCHESTRATOR_INSTANCE=`hostname`:12345 if using a port other than 3306.
#   If you do this orchestrator-client will behave the same as the orchestrator binary
#   and there will be no need to explicitly provide the parameter -i <hostname>:<port>.
#
# Usage:
#   orchestrator-client -c <command> [flags...]
# Examples:
#   orchestrator-client -c all-instances
#   orchestrator-client -c which-replicas -i some.master.com:3306
#   orchestrator-client -c which-cluster-instances --alias mycluster
#   orchestrator-client -c replication-analysis
#   orchestrator-client -c register-candidate -i candidate.host.com:3306 --promotion-rule=prefer
#   orchestrator-client -c recover -i failed.host.com:3306

# /etc/profile.d/orchestrator-client.sh is for you to set any environment.
# In particular, you will want to set ORCHESTRATOR_API
myname=$(basename $0)
[ -f /etc/profile.d/orchestrator-client.sh ] && . /etc/profile.d/orchestrator-client.sh

prepare_orchestrator_env() {
   i=0
   port_name=ORC_PORTS_${i}
   endpoint_name=ORC_ENDPOINTS_${i}
   while [[ -n "${!port_name}" ]] && [[ -n "${!endpoint_name}" ]]; do
     port=${!port_name}
     endpoint=${!endpoint_name}

     api="http://$endpoint:$port/api"

     if [[ -z "$ORCHESTRATOR_API" ]]; then
       ORCHESTRATOR_API="$api"
     else
       ORCHESTRATOR_API="$ORCHESTRATOR_API $api"
     fi
     i=$(($i+1))
     port_name=ORC_PORTS_${i}
     endpoint_name=ORC_ENDPOINTS_${i}
   done
   export ORCHESTRATOR_API=$ORCHESTRATOR_API
}

prepare_orchestrator_env

orchestrator_api="${ORCHESTRATOR_API:-http://localhost:3000}"
leader_api=

command=
instance="${ORCHESTRATOR_INSTANCE:-}"
destination=
alias=
owner="$(whoami | xargs)"
reason=
duration="10m"
promotion_rule=
tag=
pool=
hostname_flag=
api_path=
basic_auth="${ORCHESTRATOR_AUTH_USER:-}:${ORCHESTRATOR_AUTH_PASSWORD:-}"
headers_auth="${ORCHESTRATOR_AUTH_USER_HEADER}"
binlog=
seconds=

instance_hostport=
destination_hostport=
default_port=3306

api_response=
api_details=

unauthorized_401="401 Unauthorized"

for arg in "$@"; do
  shift
  case "$arg" in
    "-help"|"--help")                     set -- "$@" "-h" ;;
    "-command"|"--command")               set -- "$@" "-c" ;;
    "-alias"|"--alias")                   set -- "$@" "-a" ;;
    "-owner"|"--owner")                   set -- "$@" "-o" ;;
    "-reason"|"--reason")                 set -- "$@" "-r" ;;
    "-promotion-rule"|"--promotion-rule") set -- "$@" "-R" ;;
    "-duration"|"--duration")             set -- "$@" "-u" ;;
    "-tag"|"--tag")                       set -- "$@" "-t" ;;
    "-pool"|"--pool")                     set -- "$@" "-l" ;;
    "-hostname"|"--hostname")             set -- "$@" "-H" ;;
    "-api"|"--api")                       set -- "$@" "-U" ;;
    "-path"|"--path")                     set -- "$@" "-P" ;;
    "-query"|"--query")                   set -- "$@" "-q" ;;
    "-auth"|"--auth")                     set -- "$@" "-b" ;;
    "-headers-auth"|"--headers-auth")     set -- "$@" "-e" ;;
    "-binlog"|"--binlog")                 set -- "$@" "-n" ;;
    "-seconds"|"--seconds")               set -- "$@" "-S" ;;
    *)                                    set -- "$@" "$arg"
  esac
done

while getopts "c:i:d:s:a:D:U:o:r:u:R:t:l:H:P:q:b:e:n:h:S:" OPTION
do
  case $OPTION in
    h) command="help" ;;
    c) command="$OPTARG" ;;
    i) instance="$OPTARG" ;;
    d) destination="$OPTARG" ;;
    s) destination="$OPTARG" ;;
    a) alias="$OPTARG" ;;
    o) owner="$OPTARG" ;;
    r) reason="$OPTARG" ;;
    u) duration="$OPTARG" ;;
    R) promotion_rule="$OPTARG" ;;
    t) tag="$OPTARG" ;;
    l) pool="$OPTARG" ;;
    H) hostname_flag="$OPTARG" ;;
    D) default_port="$OPTARG" ;;
    U) [ ! -z "$OPTARG" ] && orchestrator_api="$OPTARG" ;;
    P) api_path="$OPTARG" ;;
    b) basic_auth="$OPTARG" ;;
    e) headers_auth="$OPTARG" ;;
    n) binlog="$OPTARG" ;;
    q) query="$OPTARG" ;;
    S) seconds="$OPTARG"
  esac
done

function universal_sed {
  if [[ $(uname) == "Darwin" || $(uname) == *"BSD"* ]]; then
    gsed "$@"
  else
    sed "$@"
  fi
}

function fail {
  message="$myname[$$]: $1"
  >&2 echo "$message"
  exit 1
}

function check_requirements {
  if [[ $(uname) == "Darwin" || $(uname) == *"BSD"* ]]; then
    which gsed > /dev/null 2>&1 || fail "cannot find gsed (required on BSD/Darwin systems)"
  fi
  which curl > /dev/null 2>&1 || fail "cannot find curl"
  which jq   > /dev/null 2>&1 || fail "cannot find jq"
}

function get_curl_auth_params {
  local requires_auth=""

  if [[ "${basic_auth}" != ":" ]]; then
    requires_auth="--basic --user "${basic_auth}""

    curl --help 2>&1 | fgrep -q 'disallow-username-in-url' && \
      requires_auth+=" --disallow-username-in-url"
  fi

  if [[ -n "${headers_auth}" ]]; then
    requires_auth+=" -H "${headers_auth}""
  fi

  # Test API access
  curl "${requires_auth}" -s --head "${orchestrator_api}" 2>&1 | fgrep -q "$unauthorized_401" && \
    echo "$unauthorized_401" && \
    return

  echo "${requires_auth}"
}

function assert_nonempty {
  name="$1"
  value="$2"

  if [ -z "$value" ] ; then
    fail "$name must be provided"
  fi
}

# to_hostport transforms:
# - fqdn:port => fqdn/port
# - fqdn => fqdn/default_port
function to_hostport {
  instance_key="$1"

  if [ -z "$instance_key" ] ; then
    echo ""
    return
  fi

  if [[ $instance_key == *":"* ]]; then
    echo $instance_key | tr ':' '/'
  else
    echo "$instance_key/$default_port"
  fi
}

function normalize_orchestrator_api {
  api="${1:-$orchestrator_api}"
  api=${api%/}
  if [[ ! $api == *"/api" ]]; then
    api=${api%/}
    api="$api/api"
  fi
  echo $api
}


function detect_leader_api {
  # $orchestrator_api may be a single URI (e.g. "http://orchestrator.service/api")
  # - in which case we just normalize the URL
  # or it may be a space delimited list, such as "http://host1:3000/api http://host2:3000/api http://host3:3000/api "
  # - in which case we figure out which of the URLs is the leader
  # Prevent leaking passwords if the URL has credentials like: http://<user>:<password>@host:3000/api
  local curl_auth_params="$(get_curl_auth_params)"

  if [ "${curl_auth_params}" == "$unauthorized_401" ] ; then
    santised_api=$(echo "${orchestrator_api}" | sed -e 's|:[^:^@^ ]*@|:<REMOVED>@|g')
    fail "Cannot access orchestrator at ${santised_api}.  Check ORCHESTRATOR_API is configured correctly and orchestrator is running"
  fi

  leader_api=
  apis=($orchestrator_api)
  if [ ${#apis[@]} -eq 1 ] ; then
    leader_api="$(normalize_orchestrator_api $orchestrator_api)"
    return
  fi
  for api in ${apis[@]} ; do
    api=$(normalize_orchestrator_api $api)
    leader_check=$(curl ${curl_auth_params} -m 1 -s -o /dev/null -w "%{http_code}" "${api}/leader-check")
    if [ "$leader_check" == "200" ] ; then
      leader_api="$api"
      return
    fi
  done
  # Cannot find leader directly. Maybe our config is wrong. But, perhaps one of the nodes can route us?
  for api in ${apis[@]} ; do
    api=$(normalize_orchestrator_api $api)
    leader_check=$(curl ${curl_auth_params} -m 1 -s -o /dev/null -w "%{http_code}" "${api}/routed-leader-check")
    if [ "$leader_check" == "200" ] ; then
      leader_api="$api"
      return
    fi
  done
  leader_api=${apis[0]}
}

function urlencode {
  uri="$1"
  echo "$uri" | jq -s -R -r @uri | tr -d '\n'
}

function api {
  local curl_auth_params="$(get_curl_auth_params)"

  path="$1"
  raw_output="${2:-}"

  uri="$leader_api/$path"
  # echo $uri
  set -o pipefail

  api_call_result=0
  if [[ ${curl_auth_params} != "401 Unauthorized" ]]; then
    for sleep_time in 0.1 0.2 0.5 1 2 2.5 5 0 ; do
      api_response=$(curl ${curl_auth_params} -s "$uri" | jq '.')
      api_call_result=$?
      [ $api_call_result -eq 0 ] && break
      sleep $sleep_time
    done
  else
    api_call_result=1
  fi
  if [ $api_call_result -ne 0 ] ; then
    fail "Cannot access orchestrator at ${leader_api}.  Check ORCHESTRATOR_API is configured correctly and orchestrator is running"
  fi

  if [ "$(echo $api_response | jq -r 'type')" == "array" ] ; then
    return
  fi
  if [ "$(echo $api_response | jq -r 'type')" == "string" ] ; then
    return
  fi
  if [ "$(echo $api_response | jq -r 'has("Code")')" == "false" ] ; then
    return
  fi
  api_details=$(echo $api_response | jq '.Details')
  if echo $api_response | jq -r '.Code' | grep -q "ERROR" ; then
    if [ -n "$raw_output" ] ; then
      echo $api_response
    else
      echo $api_response | jq -r '.Message' | tr -d "'" | xargs >&2 echo
      [ "$api_details" != "null" ] && echo $api_details
    fi
    exit 1
  fi
}

function print_response {
  echo $api_response
}

function print_details {
  echo $api_details
}

function filter_key {
  cat - | jq '.Key'
}

function filter_master_key {
  cat - | jq '.MasterKey'
}

function filter_keys {
  cat - | jq '.[] | .Key'
}

function filter_broken_replicas {
  cat - | jq '.[] | select((.ReplicationSQLThreadRuning == false or .ReplicationIOThreadRuning == false) and (.LastSQLError != "" or .LastIOError != "")) | [.]'
}

function filter_running_replicas {
  cat - | jq '.[] | select(.ReplicationSQLThreadRuning == true and .ReplicationIOThreadRuning == true) | [.]'
}

function print_key {
  cat - | jq -r '. | (.Hostname + ":" + (.Port | tostring))'
}

function print_keys {
  cat - | jq -r '.[]' | print_key
}

function which_api {
  echo "$leader_api"
}

function api_call {
  assert_nonempty "path" "$api_path"
  api "$api_path" "true"
  print_response
}

function prompt_help {
  echo "Usage: orchestrator-client -c <command> [flags...]"
  echo "Example: orchestrator-client -c which-master -i some.replica"
  echo "Options:"
  echo "
  -h, --help
    print this help
  -c <command>, --command <command>
    indicate the operation to perform (see listing below)
  -a <alias>, --alias <alias>
    cluster alias
  -o <owner>, --owner <owner>
    name of owner for downtime/maintenance commands
  -r <reason>, --reason <reason>
    reason for downtime/maintenance operation
  -u <duration>, --duration <duration>
    duration for downtime/maintenance operations
  -R <promotion rule>, --promotion-rule <promotion rule>
    rule for 'register-candidate' command
  -U <orchestrator_api>, --api <orchestrator_api>
    override \$orchestrator_api environment variable,
    indicate where the client should connect to.
  -P <api path>, --path <api path>
    With '-c api', indicate the specific API path you wish to call
  -b <username:password>, --auth <username:password>
    Specify when orchestrator uses basic HTTP auth.
  -e <header:user>, --headers-auth <header:user>
    Specify when orchestrator uses headers auth.
  -q <query>, --query <query>
    Indicate query for 'restart-replica-statements' command
  -l <pool name>, --pool <pool name>
    pool name for pool related commands
  -H <hostname> -h <hostname>
    indicate host for resolve and raft operations
  -S <seconds> --seconds
    seconds for delaying replication
"

  cat "$0" | universal_sed -n '/run_command/,/esac/p' | egrep '".*"[)].*;;' | universal_sed -r -e 's/"(.*?)".*#(.*)/\1~\2/' | column -t -s "~"
}

function async_discover {
  assert_nonempty "instance" "$instance_hostport"
  api "async-discover/$instance_hostport"
  print_details | filter_key | print_key
}

function discover {
  assert_nonempty "instance" "$instance_hostport"
  api "discover/$instance_hostport"
  print_details | filter_key | print_key
}

function ascii_topology {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  api "topology/${alias:-$instance}"
  echo "$api_response" | jq -r '.Details'
}

function ascii_topology_tabulated {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  api "topology-tabulated/${alias:-$instance}"
  echo "$api_response" | jq -r '.Details'
}

function ascii_topology_tags {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  api "topology-tags/${alias:-$instance}"
  echo "$api_response" | jq -r '.Details'
}

function snapshot_topologies {
  api "snapshot-topologies"
  echo "$api_response" | jq -r '.Details'
}

function search {
  assert_nonempty "instance" "$instance"
  api "search?s=$(urlencode "$instance")"
  print_response | filter_keys | print_key
}

function restart_replica_statements {
  assert_nonempty "instance" "$instance"
  assert_nonempty "query" "$query"
  api "restart-replica-statements/${instance_hostport}?q=$(urlencode "$query")"
  print_response | print_details
}

function can_replicate_from {
  assert_nonempty "instance" "$instance_hostport"
  assert_nonempty "destination" "$destination_hostport"
  api "can-replicate-from/$instance_hostport/$destination_hostport"

  if print_response | jq -r '.Message' | grep -q "true" ; then
    print_response | print_details | print_key
  fi
}

function can_replicate_from_gtid {
  assert_nonempty "instance" "$instance_hostport"
  assert_nonempty "destination" "$destination_hostport"
  api "can-replicate-from-gtid/$instance_hostport/$destination_hostport"

  if print_response | jq -r '.Message' | grep -q "true" ; then
    print_response | print_details | print_key
  fi
}

function is_replicating {
  assert_nonempty "instance" "$instance_hostport"
  api "instance/$instance_hostport"

  print_response | jq '. | select(.ReplicationSQLThreadState==1 and .ReplicationIOThreadState==1)' | filter_key | print_key
}

function is_replication_stopped {
  assert_nonempty "instance" "$instance_hostport"
  api "instance/$instance_hostport"

  print_response | jq '. | select(.ReplicationSQLThreadState==0 and .ReplicationIOThreadState==0)' | filter_key | print_key
}

function purge_binary_logs {
  assert_nonempty "instance" "$instance_hostport"
  assert_nonempty "binlog" "$binlog"
  api "purge-binary-logs/$instance_hostport/$binlog"
  print_details | filter_key | print_key
}

function which_gtid_errant {
  assert_nonempty "instance" "$instance_hostport"
  api "instance/$instance_hostport"
  print_response | jq -r '.GtidErrant'
}

function locate_gtid_errant {
  assert_nonempty "instance" "$instance_hostport"
  api "locate-gtid-errant/$instance_hostport"
  print_response | print_details | jq -r '.[]'
}

function last_pseudo_gtid {
  assert_nonempty "instance" "$instance_hostport"
  api "last-pseudo-gtid/$instance_hostport"
  print_response | print_details | jq -r '.'
}

function instance {
  assert_nonempty "instance" "$instance_hostport"
  api "instance/$instance_hostport"
  print_response | filter_key | print_key
}

function which_master {
  assert_nonempty "instance" "$instance_hostport"
  api "instance/$instance_hostport"
  print_response | filter_master_key | print_key
}

function which_replicas {
  assert_nonempty "instance" "$instance_hostport"
  api "instance-replicas/$instance_hostport"
  print_response | filter_keys | print_key
}

function which_broken_replicas {
  assert_nonempty "instance" "$instance_hostport"
  api "instance-replicas/$instance_hostport"
  print_response | filter_broken_replicas | filter_keys | print_key
}

function which_cluster {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  api "cluster-info/${alias:-$instance}"
  print_response | jq -r '.ClusterName'
}

function which_cluster_alias {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  api "cluster-info/${alias:-$instance}"
  print_response | jq -r '.ClusterAlias'
}

function which_cluster_master {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  api "master/${alias:-$instance}"
  print_response | jq -r '.ClusterName'
}

function which_cluster_instances {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  api "cluster/${alias:-$instance}"
  print_response | filter_keys | print_key
}

function all_clusters_masters {
  api "masters"
  print_response | filter_keys | print_key
}

function clusters {
  api "clusters-info"
  print_response | jq -r '.[].ClusterName'
}

function clusters_alias {
  api "clusters-info"
  print_response | jq -r '.[] | (.ClusterName + "," + .ClusterAlias)'
}

function forget {
  assert_nonempty "instance" "$instance_hostport"
  api "forget/$instance_hostport"
}

function forget_cluster {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  api "forget-cluster/${alias:-$instance}"
}


function all_instances {
  api "all-instances"
  print_response | filter_keys | print_key
}

function which_cluster_osc_replicas {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  api "cluster-osc-replicas/${alias:-$instance}"
  print_response | filter_keys | print_key
}

function which_cluster_osc_running_replicas {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  api "cluster-osc-replicas/${alias:-$instance}"
  print_response | filter_running_replicas | filter_keys | print_key
}

function downtimed {
  api "downtimed/${alias:-$instance}"
  print_response | filter_keys | print_key
}

function dominant_dc {
  api "masters"
  print_response | jq -r '.[].DataCenter' | sort | uniq -c | sort -nr | head -n 1 | awk '{print $2}'
}

function tags {
  assert_nonempty "instance" "$instance_hostport"
  api "tags/$instance_hostport"

  print_response | jq -r '.[]'
}

function tag_value {
  assert_nonempty "instance" "$instance_hostport"
  assert_nonempty "tag" "$tag"
  api "tag-value/${instance_hostport}?tag=$(urlencode "$tag")"

  print_response | jq -r '.'
}

function tag {
  assert_nonempty "instance" "$instance_hostport"
  assert_nonempty "tag" "$tag"
  api "tag/${instance_hostport}?tag=$(urlencode "$tag")"

  print_details | print_key
}

function untag {
  assert_nonempty "instance" "$instance_hostport"
  assert_nonempty "tag" "$tag"
  api "untag/${instance_hostport}?tag=$tag"

  print_details | print_keys
}

function untag_all {
  assert_nonempty "tag" "$tag"
  api "untag-all?tag=$tag"

  print_details | print_keys
}

function tagged {
  assert_nonempty "tag" "$tag"
  api "tagged/${instance_hostport}?tag=$(urlencode "$tag")"

  print_response | print_keys
}

function submit_masters_to_kv_stores {
  api "submit-masters-to-kv-stores/${alias}"
  print_details | jq -r '.[] | (.Key + ":" + .Value)'
}

function submit_pool_instances {
  # 'instance' is comma delimited, e.g.
  #   myinstance1.com:3306,myinstance2.com:3306,myinstance3.com:3306
  assert_nonempty "instance" "$instance"
  assert_nonempty "pool" "$pool"
  api "submit-pool-instances/$pool?instances=$(urlencode "$instance")"
  print_details | jq -r .
}

function which_heuristic_cluster_pool_instances {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  # pool is optional
  api "heuristic-cluster-pool-instances/${alias:-$instance}/${pool}"
  print_details | filter_keys | print_key
}

function begin_downtime {
  assert_nonempty "instance" "$instance_hostport"
  assert_nonempty "owner" "$owner"
  assert_nonempty "reason" "$reason"
  assert_nonempty "duration" "$duration"
  api "begin-downtime/$instance_hostport/$(urlencode "$owner")/$(urlencode "$reason")/$duration"
  print_details | print_key
}

function end_downtime {
  assert_nonempty "instance" "$instance_hostport"
  api "end-downtime/$instance_hostport"
  print_details | print_key
}

function begin_maintenance {
  assert_nonempty "instance" "$instance_hostport"
  assert_nonempty "owner" "$owner"
  assert_nonempty "reason" "$reason"
  api "begin-maintenance/$instance_hostport/$(urlencode "$owner")/$(urlencode "$reason")"
  print_details | print_key
}

function end_maintenance {
  assert_nonempty "instance" "$instance_hostport"
  api "end-maintenance/$instance_hostport"
  print_details | print_key
}

function register_candidate {
  assert_nonempty "instance" "$instance_hostport"
  assert_nonempty "promotion-rule" "$promotion_rule"
  api "register-candidate/$instance_hostport/$promotion_rule"
  print_details | print_key
}

function register_hostname_unresolve {
  assert_nonempty "instance" "$instance_hostport"
  assert_nonempty "hostname" "$hostname_flag"
  api "register-hostname-unresolve/$instance_hostport/$hostname_flag"
  print_details | print_key
}

function deregister_hostname_unresolve {
  assert_nonempty "instance" "$instance_hostport"
  api "deregister-hostname-unresolve/$instance_hostport"
  print_details | print_key
}

function general_singular_relocate_command {
  path="${1:-$command}"

  assert_nonempty "instance" "$instance_hostport"
  api "${path}/$instance_hostport"
  echo "$(print_details | filter_key | print_key)<$(print_details | filter_master_key | print_key)"
}

function general_relocate_command {
  path="${1:-$command}"

  assert_nonempty "instance" "$instance_hostport"
  assert_nonempty "destination" "$destination_hostport"
  api "${path}/$instance_hostport/$destination_hostport"
  echo "$(print_details | filter_key | print_key)<$(print_details | filter_master_key | print_key)"
}

function general_singular_relocate_replicas_command {
  path="${1:-$command}"

  assert_nonempty "instance" "$instance_hostport"
  api "${path}/$instance_hostport/$destination_hostport"
  print_details | filter_keys | print_key
}

function general_relocate_replicas_command {
  path="${1:-$command}"

  assert_nonempty "instance" $instance_hostport
  assert_nonempty "destination" $destination_hostport
  api "${path}/$instance_hostport/$destination_hostport"
  print_details | filter_keys | print_key
}

function relocate {
  assert_nonempty "instance" "$instance_hostport"
  assert_nonempty "destination" "$destination_hostport"
  api "relocate/$instance_hostport/$destination_hostport"
  echo "$(print_details | filter_key | print_key)<$(print_details | filter_master_key | print_key)"
}

function relocate_replicas {
  assert_nonempty "instance" $instance_hostport
  assert_nonempty "destination" $destination_hostport
  api "relocate-replicas/$instance_hostport/$destination_hostport"
  print_details | filter_keys | print_key
}

function general_instance_command {
  path="${1:-$command}"

  assert_nonempty "instance" "$instance_hostport"
  api "$path/$instance_hostport"
  print_details | filter_key | print_key
}

function delay_replication_command {
  path="${1:-$command}"

  assert_nonempty "instance" "$instance_hostport"
  assert_nonempty "seconds" "$seconds"
  api "$path/$instance_hostport/$seconds"
  print_details
}

function replication_analysis {
  api "replication-analysis"
  print_details | jq -r '.[] |
    if .Analysis == "NoProblem" then
      (.AnalyzedInstanceKey.Hostname + ":" + (.AnalyzedInstanceKey.Port | tostring) + " (cluster " + .ClusterDetails.ClusterName + "): ") + .StructureAnalysis[0]
    else
      (.AnalyzedInstanceKey.Hostname + ":" + (.AnalyzedInstanceKey.Port | tostring) + " (cluster " + .ClusterDetails.ClusterName + "): ") + .Analysis
    end
    '
}

function recover {
  assert_nonempty "instance" "$instance_hostport"
  api "recover/$instance_hostport"
  print_details | print_key
}

function graceful_master_takeover {
  assert_nonempty "instance|alias" "${alias:-$instance}"

  if [ -z "$destination_hostport" ] ; then
    # No destination given.
    api "graceful-master-takeover/${alias:-$instance}"
  else
    # Explicit destination (designated master) given
    api "graceful-master-takeover/${alias:-$instance}/${destination_hostport}"
  fi
  print_details | jq '.SuccessorKey' | print_key
}

function graceful_master_takeover_auto {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  if [ -z "$destination_hostport" ] ; then
    # No destination given.
    api "graceful-master-takeover-auto/${alias:-$instance}"
  else
    # Explicit destination (designated master) given
    api "graceful-master-takeover-auto/${alias:-$instance}/${destination_hostport}"
  fi
  print_details | jq '.SuccessorKey' | print_key
}

function force_master_failover {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  api "force-master-failover/${alias:-$instance}"
  print_details | jq '.SuccessorKey' | print_key
}

function force_master_takeover {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  assert_nonempty "destination" $destination_hostport
  api "force-master-takeover/${alias:-$instance}/${destination_hostport}"
  print_details | jq '.SuccessorKey' | print_key
}

function ack_cluster_recoveries {
  assert_nonempty "instance|alias" "${alias:-$instance}"
  assert_nonempty "reason" "$reason"
  api "ack-recovery/cluster/${alias:-$instance}?comment=$(urlencode $reason)"
  print_details | jq -r .
}

function ack_all_recoveries {
  assert_nonempty "reason" "$reason"
  api "ack-all-recoveries?comment=$(urlencode $reason)"
  print_details | jq -r .
}

function disable_global_recoveries {
  api "disable-global-recoveries"
  print_details | jq -r .
}

function enable_global_recoveries {
  api "enable-global-recoveries"
  print_details | jq -r .
}

function check_global_recoveries {
  api "check-global-recoveries"
  print_details | jq -r .
}

function raft_leader {
  api "raft-state"
  if print_response | jq -r . | grep -q Leader ; then
    # confirmed raft is running well
    api "raft-leader"
    print_response | jq -r '.'
  else
    fail "Cannot determine raft state"
  fi
}

function raft_health {
  api "raft-health"
  print_response | jq -r '.'
}

function raft_leader_hostname {
  api "raft-state"
  if print_response | jq -r . | grep -q Leader ; then
    # confirmed raft is running well
    api "status"
    print_details | jq -r '.Hostname'
  else
    fail "Cannot determine raft state"
  fi
}

# raft_elect_leader elects the raft leader by using --hostname as hint
function raft_elect_leader {
  assert_nonempty "hostname" "$hostname_flag"
  api "raft-state"
  if print_response | jq -r . | grep -q Leader ; then
    # confirmed raft is running well
    api "raft-yield-hint/${hostname_flag}"
    print_details | jq -r .
  else
    fail "Cannot determine raft state"
  fi
}

function run_command {
  if [ -z "$command" ] ; then
    fail "No command given. Use $myname -c <command> [...] or $myname --command <command> [...] to do something useful"
  fi
  command=$(echo $command | universal_sed -e 's/slave/replica/')
  case $command in
    "help") prompt_help ;; # Show available commands

    "which-api") which_api ;; # Output the HTTP API to be used
    "api") api_call ;;        # Invoke any API request; provide --path argument

    "async-discover") async_discover ;;                         # Lookup an instance, investigate it asynchronously. Useful for bulk loads
                                                                # of servers into an empty orchestrator cluster.
    "discover") discover ;;                                     # Lookup an instance, investigate it
    "forget") forget ;;                                         # Forget about an instance's existence
    "forget-cluster") forget_cluster ;;                         # Forget about a cluster

    "topology") ascii_topology ;;                               # Show an ascii-graph of a replication topology, given a member of that topology
    "topology-tabulated") ascii_topology_tabulated ;;           # Show an ascii-graph of a replication topology, given a member of that topology, in tabulated format
    "topology-tags") ascii_topology_tags ;;                     # Show an ascii-graph of a replication topology and instance tags, given a member of that topology
    "snapshot-topologies") snapshot_topologies ;;               # Trigger topology snapshot (recording host/master settings for all hosts)
    "clusters") clusters ;;                                     # List all clusters known to orchestrator
    "clusters-alias") clusters_alias ;;                         # List all clusters known to orchestrator
    "search") search ;;                                         # Search for instances matching given substring
    "instance"|"which-instance") instance ;;                    # Output the fully-qualified hostname:port representation of the given instance, or error if unknown
    "which-master") which_master ;;                             # Output the fully-qualified hostname:port representation of a given instance's master
    "which-replicas") which_replicas ;;                         # Output the fully-qualified hostname:port list of replicas of a given instance
    "which-broken-replicas") which_broken_replicas ;;           # Output the fully-qualified hostname:port list of broken replicas of a given instance
    "which-cluster-instances") which_cluster_instances ;;       # Output the list of instances participating in same cluster as given instance
    "which-cluster") which_cluster ;;                           # Output the name of the cluster an instance belongs to, or error if unknown to orchestrator
    "which-cluster-alias") which_cluster_alias ;;               # Output the alias of the cluster an instance belongs to, or error if unknown to orchestrator
    "which-cluster-master") which_cluster_master ;;             # Output the name of a writable master in given cluster
    "all-clusters-masters") all_clusters_masters ;;             # List of writeable masters, one per cluster
    "all-instances") all_instances ;;                           # The complete list of known instances
    "which-cluster-osc-replicas") which_cluster_osc_replicas ;; # Output a list of replicas in a cluster, that could serve as a pt-online-schema-change operation control replicas
    "which-cluster-osc-running-replicas") which_cluster_osc_running_replicas ;; # Output a list of healthy, replicating replicas in a cluster, that could serve as a pt-online-schema-change operation control replicas
    "downtimed") downtimed ;;                                   # List all downtimed instances
    "dominant-dc") dominant_dc ;;                               # Name the data center where most masters are found

    "submit-masters-to-kv-stores") submit_masters_to_kv_stores;; # Submit a cluster's master, or all clusters' masters to KV stores

    "relocate") general_relocate_command ;;                   # Relocate a replica beneath another instance
    "relocate-replicas") general_relocate_replicas_command ;; # Relocates all or part of the replicas of a given instance under another instance

    "match") general_relocate_command ;;                               # Matches a replica beneath another (destination) instance using Pseudo-GTID
    "match-up") general_singular_relocate_command ;;                   # Transport the replica one level up the hierarchy, making it child of its grandparent, using Pseudo-GTID
    "match-up-replicas") general_singular_relocate_replicas_command ;; # Matches replicas of the given instance one level up the topology, making them siblings of given instance, using Pseudo-GTID

    "move-up") general_singular_relocate_command ;;                    # Move a replica one level up the topology
    "move-below") general_relocate_command ;;                          # Moves a replica beneath its sibling. Both replicas must be actively replicating from same master.
    "move-equivalent") general_relocate_command ;;                     # Moves a replica beneath another server, based on previously recorded "equivalence coordinates"
    "move-up-replicas") general_singular_relocate_replicas_command ;;  # Moves replicas of the given instance one level up the topology
    "make-co-master") general_singular_relocate_command ;;             # Create a master-master replication. Given instance is a replica which replicates directly from a master.
    "take-master") general_singular_relocate_command ;;                # Turn an instance into a master of its own master; essentially switch the two.

    "move-gtid") general_relocate_command ;;                           # Move a replica beneath another instance via GTID
    "move-replicas-gtid") general_relocate_replicas_command ;;         # Moves all replicas of a given instance under another (destination) instance using GTID

    "repoint") general_relocate_command ;;                             # Make the given instance replicate from another instance without changing the binglog coordinates. Use with care
    "repoint-replicas") general_singular_relocate_replicas_command ;;  # Repoint all replicas of given instance to replicate back from the instance. Use with care
    "take-siblings") general_singular_relocate_command ;;              # Turn all siblings of a replica into its sub-replicas.

    "tags")      tags      ;;   # List tags for a given instance
    "tag-value") tag_value ;;   # List tags for a given instance
    "tag")       tag       ;;   # Add a tag to a given instance. Tag in "tagname" or "tagname=tagvalue" format
    "untag")     untag     ;;   # Remove a tag from an instance
    "untag-all") untag_all ;;   # Remove a tag from all matching instances
    "tagged")    tagged    ;;   # List instances tagged by tag-string. Format: "tagname" or "tagname=tagvalue" or comma separated "tag0,tag1=val1,tag2" for intersection of all.

    "submit-pool-instances") submit_pool_instances ;;                  # Submit a pool name with a list of instances in that pool
    "which-heuristic-cluster-pool-instances") which_heuristic_cluster_pool_instances ;; # List instances of a given cluster which are in either any pool or in a specific pool

    "begin-downtime") begin_downtime ;;                               # Mark an instance as downtimed
    "end-downtime") end_downtime ;;                                   # Indicate an instance is no longer downtimed
    "begin-maintenance") begin_maintenance ;;                         # Request a maintenance lock on an instance
    "end-maintenance") end_maintenance ;;                             # Remove maintenance lock from an instance
    "register-candidate") register_candidate ;;                       # Indicate the promotion rule for a given instance
    "register-hostname-unresolve") register_hostname_unresolve ;;     # Assigns the given instance a virtual (aka "unresolved") name
    "deregister-hostname-unresolve") deregister_hostname_unresolve ;; # Explicitly deregister/dosassociate a hostname with an "unresolved" name

    "stop-replica") general_instance_command ;;                 # Issue a STOP SLAVE on an instance
    "stop-replica-nice") general_instance_command ;;            # Issue a STOP SLAVE on an instance, make effort to stop such that SQL thread is in sync with IO thread (ie all relay logs consumed)
    "start-replica") general_instance_command ;;                # Issue a START SLAVE on an instance
    "restart-replica") general_instance_command ;;              # Issue STOP and START SLAVE on an instance
    "reset-replica") general_instance_command ;;                # Issues a RESET SLAVE command; use with care
    "detach-replica") general_instance_command ;;               # Stops replication and modifies Master_Host into an impossible yet reversible value.
    "reattach-replica") general_instance_command ;;             # Undo a detach-replica operation
    "detach-replica-master-host") general_instance_command ;;   # Stops replication and modifies Master_Host into an impossible yet reversible value.
    "reattach-replica-master-host") general_instance_command ;; # Undo a detach-replica-master-host operation
    "skip-query") general_instance_command ;;                   # Skip a single statement on a replica; either when running with GTID or without
    "which-gtid-errant") which_gtid_errant ;;                   # Get errant GTID set (empty results if no errant GTID)
    "locate-gtid-errant") locate_gtid_errant ;;                 # List binary logs containing errant GTID
    "gtid-errant-reset-master") general_instance_command ;;     # Remove errant GTID transactions by way of RESET MASTER
    "gtid-errant-inject-empty") general_instance_command ;;     # Apply errant GTID as empty transactions on cluster's master
    "enable-semi-sync-master") general_instance_command ;;      # Enable semi-sync (master-side)
    "disable-semi-sync-master") general_instance_command ;;     # Disable semi-sync (master-side)
    "enable-semi-sync-replica") general_instance_command ;;     # Enable semi-sync (replica-side)
    "disable-semi-sync-replica") general_instance_command ;;    # Disable semi-sync (replica-side)
    "restart-replica-statements") restart_replica_statements ;; # Given `-q "<query>"` that requires replication restart to apply, wrap query with stop/start slave statements as required to restore instance to same replication state. Print out set of statements
    "delay-replication") delay_replication_command ;;           # Issue a CHANGE MASTER TO DELAY=seconds preserving the replication threads state
    "can-replicate-from") can_replicate_from ;;           # Check if an instance can potentially replicate from another, according to replication rules
    "can-replicate-from-gtid") can_replicate_from_gtid ;; # Check if an instance can potentially replicate from another, according to replication rules and assuming Oracle GTID
    "is-replicating") is_replicating ;;                   # Check if an instance is replicating at this time (both SQL and IO threads running)
    "is-replication-stopped") is_replication_stopped ;;   # Check if both SQL and IO threads state are both strictly stopped.

    "set-read-only") general_instance_command ;;     # Turn an instance read-only, via SET GLOBAL read_only := 1
    "set-writeable") general_instance_command ;;     # Turn an instance writeable, via SET GLOBAL read_only := 0
    "flush-binary-logs") general_instance_command ;; # Flush binary logs on an instance
    "purge-binary-logs") purge_binary_logs        ;; # Purge binary logs on an instance
    "last-pseudo-gtid") last_pseudo_gtid ;;          # Dump last injected Pseudo-GTID entry on a server

    "recover") recover ;;                                     # Do auto-recovery given a dead instance, assuming orchestrator agrees there's a problem. Override blocking.
    "graceful-master-takeover") graceful_master_takeover ;;   # Gracefully promote a new master. Either indicate identity of new master via '-d designated.instance.com' or setup replication tree to have a single direct replica to the master.
    "graceful-master-takeover-auto") graceful_master_takeover_auto ;; # Gracefully promote a new master. orchestrator will attempt to pick the promoted replica automatically
    "force-master-failover") force_master_failover ;;         # Forcibly discard master and initiate a failover, even if orchestrator doesn't see a problem. This command lets orchestrator choose the replacement master
    "force-master-takeover") force_master_takeover ;;         # Forcibly discard master and promote another (direct child) instance instead, even if everything is running well
    "ack-cluster-recoveries") ack_cluster_recoveries ;;       # Acknowledge recoveries for a given cluster; this unblocks pending future recoveries
    "ack-all-recoveries") ack_all_recoveries ;;               # Acknowledge all recoveries
    "disable-global-recoveries") disable_global_recoveries ;; # Disallow orchestrator from performing recoveries globally
    "enable-global-recoveries") enable_global_recoveries ;;   # Allow orchestrator to perform recoveries globally
    "check-global-recoveries") check_global_recoveries ;;     # Show the global recovery configuration

    "replication-analysis") replication_analysis ;;           # Request an analysis of potential crash incidents in all known topologies

    "raft-leader") raft_leader ;;                   # Get identify of raft leader, assuming raft setup
    "raft-health") raft_health ;;                   # Whether node is part of a healthy raft group
    "raft-leader-hostname") raft_leader_hostname ;; # Get hostname of raft leader, assuming raft setup
    "raft-elect-leader") raft_elect_leader ;;       # Request raft re-elections, provide hint for new leader's identity
    *) fail "Unsupported command $command" ;;
  esac
}

function main {

  detect_leader_api

  instance_hostport=$(to_hostport $instance)
  destination_hostport=$(to_hostport $destination)

  run_command
}

main