#!/bin/sh

redis_base_cmd="redis-cli $REDIS_CLI_TLS_CMD -p $SENTINEL_SERVICE_PORT -a $SENTINEL_PASSWORD"
$redis_base_cmd ${KB_ACCOUNT_STATEMENT}
$redis_base_cmd acl save
