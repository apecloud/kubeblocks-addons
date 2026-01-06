#!/bin/sh

if [ "$TLS_ENABLED" == "true" ]; then
    redis_base_cmd="redis-cli -p $SENTINEL_SERVICE_PORT -a $SENTINEL_PASSWORD --tls --cacert ${TLS_MOUNT_PATH}/ca.crt"
else
    redis_base_cmd="redis-cli -p $SENTINEL_SERVICE_PORT -a $SENTINEL_PASSWORD"
fi

$redis_base_cmd ${KB_ACCOUNT_STATEMENT}
$redis_base_cmd acl save
