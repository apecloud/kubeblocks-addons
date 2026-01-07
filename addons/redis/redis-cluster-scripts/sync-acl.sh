#!/bin/bash

redis_base_cmd="redis-cli -p $SERVICE_PORT -a $REDIS_DEFAULT_PASSWORD $REDIS_CLI_TLS_CMD"
if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
   redis_base_cmd="redis-cli -p $SERVICE_PORT $REDIS_CLI_TLS_CMD"
fi

is_ok=false
acl_list=""
# 1. get acl list from other pods
for pod_fqdn in $(echo "$CURRENT_SHARD_POD_FQDN_LIST" | tr ',' '\n'); do
    if [[ "$pod_fqdn" == "$KB_JOIN_MEMBER_POD_FQDN" ]]; then
        continue
    fi
    acl_list=$($redis_base_cmd -h "$pod_fqdn" ACL LIST)
    if [ $? -eq 0 ]; then
        is_ok=true
        break
    fi
done

if [ "$is_ok" = false ]; then
    echo "Failed to get ACL LIST from other pods" >&2
    exit 1
fi

if [ -z "$acl_list" ]; then
    echo "No ACL rules found in other pods, skip synchronization" >&2
    exit 0
fi

set -e
# 2. apply acl list to current pod
while IFS= read -r user_rule; do
    [[ -z "$user_rule" ]] && continue

    if [[ "$user_rule" =~ ^user[[:space:]]+([^[:space:]]+) ]]; then
        username="${BASH_REMATCH[1]}"
    else
      # skip invalid user rule
      continue
    fi

    if [[ "$username" == "default" ]]; then
        continue
    fi
    rule_part="${user_rule#user $username }"
    $redis_base_cmd -h $KB_JOIN_MEMBER_POD_FQDN ACL SETUSER "$username" $rule_part >&2
done <<< "$acl_list"

$redis_base_cmd -h $KB_JOIN_MEMBER_POD_FQDN ACL save >&2