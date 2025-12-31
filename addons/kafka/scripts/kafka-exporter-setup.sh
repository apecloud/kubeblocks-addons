#!/bin/bash
set -e

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

generate_kafka_servers() {
  local servers=""
  
  if [[ -z "$BROKER_POD_FQDN_LIST" ]] && [[ -z "$COMBINE_POD_FQDN_LIST" ]]; then
    echo "Error: BROKER_POD_FQDN_LIST and COMBINE_POD_FQDN_LIST environment variable is not set, Please check and try again." >&2
    return 1
  fi

  ## try to use COMBINE_POD_FQDN_LIST first
  if [[ -n "$COMBINE_POD_FQDN_LIST" ]]; then
    IFS=',' read -r -a combine_pod_fqdn_list <<< "$COMBINE_POD_FQDN_LIST"
    for pod_fqdn in "${combine_pod_fqdn_list[@]}"; do
      servers="${servers} --kafka.server=${pod_fqdn}:9094"
    done
    echo "$servers"
    return 0
  fi

  # if COMBINE_POD_FQDN_LIST is not set, use BROKER_POD_FQDN_LIST
  IFS=',' read -r -a broker_pod_fqdn_list <<< "$BROKER_POD_FQDN_LIST"
  for pod_fqdn in "${broker_pod_fqdn_list[@]}"; do
    servers="${servers} --kafka.server=${pod_fqdn}:9094"
  done
  echo "$servers"
  return 0
}

get_start_kafka_exporter_cmd() {
  local servers
  local status
  servers=$(generate_kafka_servers)
  status=$?
  if [[ $status -ne 0 ]]; then
    echo "failed to generate kafka servers. Exiting." >&2
    return 1
  fi

  saslArgs=""
  if [[ $(is_sasl_enabled "${KB_CLUSTER_WITH_ZK:-false}") == "true" ]]; then 
    echo "sasl is enabled, setting sasl args" >&2
    local default_mechanism=$(get_client_default_mechanism "${KB_CLUSTER_WITH_ZK:-false}")
    echo "sasl mechanism from config: $default_mechanism" >&2
    saslArgs=$(get_kafka_exporter_sasl_args_by_mechanism "$default_mechanism")
  fi 

  if [[ -n "$TLS_ENABLED" ]]; then
    echo "TLS_ENABLED is set to true, start kafka_exporter with tls enabled." >&2
    echo "kafka_exporter --web.listen-address=:9308 --tls.enabled ${servers} $saslArgs"
  else
    echo "TLS_ENABLED is not set, start kafka_exporter with tls disabled." >&2
    echo "kafka_exporter --web.listen-address=:9308 ${servers} $saslArgs"
  fi
  return 0
}

get_kafka_exporter_sasl_args_by_mechanism() {
  local user_var_name=${KAFKA_ADMIN_USER_BROKER}
  local password_var_name=${KAFKA_ADMIN_PASSWORD_BROKER}

  if [[ -z "$user_var_name" ]]; then
    user_var_name="$KAFKA_ADMIN_USER_COMBINE"
    password_var_name="$KAFKA_ADMIN_PASSWORD_COMBINE"
  fi
  
  local mechanism="$1"
  case "${mechanism,,}" in
    "scram-sha512")
      echo "--sasl.enabled --sasl.mechanism=scram-sha512 --sasl.username=$user_var_name --sasl.password=$password_var_name"
      ;;
    "scram-sha256")
      echo "--sasl.enabled --sasl.mechanism=scram-sha256 --sasl.username=$user_var_name --sasl.password=$password_var_name"
      ;;
    "plain")
      echo "--sasl.enabled --sasl.mechanism=plain --sasl.username=$user_var_name --sasl.password=$password_var_name"
      ;;
    *)
      echo "invalid or not supported sasl mechanism: $mechanism" >&2
      return 1
      ;;
  esac
}


start_kafka_exporter() {
  local cmd
  cmd=$(get_start_kafka_exporter_cmd)
  status=$?
  if [[ $status -ne 0 ]]; then
    echo "failed to get start kafka_exporter command. Exiting." >&2
    exit 1
  fi
  $cmd
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
start_kafka_exporter
