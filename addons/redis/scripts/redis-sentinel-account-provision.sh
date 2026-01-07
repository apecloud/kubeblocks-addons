#!/bin/sh

redis_base_cmd="redis-cli -p $SENTINEL_SERVICE_PORT -a $SENTINEL_PASSWORD $REDIS_CLI_TLS_CMD"
$redis_base_cmd ${KB_ACCOUNT_STATEMENT}
$redis_base_cmd acl save
