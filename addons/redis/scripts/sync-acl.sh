#!/bin/bash

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  set -e;
}

service_port=${SERVICE_PORT:-6379}

build_redis_base_cmd() {
  local password="$1"
  local tls_cmd="$2"
  if [ -n "$password" ]; then
    echo "redis-cli $tls_cmd -p $service_port -a $password"
  else
    echo "redis-cli $tls_cmd -p $service_port"
  fi
}

fetch_acl_list_from_peers() {
  local pod_fqdn_list="$1"
  local self_fqdn="$2"
  local redis_cmd="$3"

  local is_ok=false
  local acl_list=""
  for pod_fqdn in $(echo "$pod_fqdn_list" | tr ',' '\n'); do
    if [[ "$pod_fqdn" == "$self_fqdn" ]]; then
      continue
    fi
    acl_list=$($redis_cmd -h "$pod_fqdn" ACL LIST)
    if [ $? -eq 0 ]; then
      is_ok=true
      break
    fi
  done

  if [ "$is_ok" = false ]; then
    echo "Failed to get ACL LIST from other pods" >&2
    return 1
  fi

  if [ -z "$acl_list" ]; then
    echo "No ACL rules found in other pods, skip synchronization" >&2
    return 0
  fi

  echo "$acl_list"
}

apply_acl_rules() {
  set -e
  local acl_list="$1"
  local target_fqdn="$2"
  local redis_cmd="$3"

  while IFS= read -r user_rule; do
    [[ -z "$user_rule" ]] && continue

    if [[ "$user_rule" =~ ^user[[:space:]]+([^[:space:]]+) ]]; then
      username="${BASH_REMATCH[1]}"
    else
      continue
    fi

    if [[ "$username" == "default" ]]; then
      continue
    fi
    rule_part="${user_rule#user $username }"
    if ! $redis_cmd -h "$target_fqdn" ACL SETUSER "$username" $rule_part >&2; then
      return 1
    fi
  done <<< "$acl_list"

  $redis_cmd -h "$target_fqdn" ACL save >&2
}

main() {
  local redis_base_cmd
  redis_base_cmd=$(build_redis_base_cmd "$REDIS_DEFAULT_PASSWORD" "$REDIS_CLI_TLS_CMD")

  local acl_list
  acl_list=$(fetch_acl_list_from_peers "$REDIS_POD_FQDN_LIST" "$KB_JOIN_MEMBER_POD_FQDN" "$redis_base_cmd")
  local rc=$?
  if [ $rc -ne 0 ]; then
    exit 1
  fi

  if [ -z "$acl_list" ]; then
    exit 0
  fi

  apply_acl_rules "$acl_list" "$KB_JOIN_MEMBER_POD_FQDN" "$redis_base_cmd"
}

# This is magic for shellspec ut framework.
${__SOURCED__:+false} : || return 0

main
