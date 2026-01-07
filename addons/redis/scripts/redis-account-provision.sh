#!/bin/sh
redis_base_cmd="redis-cli -p $SERVICE_PORT -a $REDIS_DEFAULT_PASSWORD $REDIS_CLI_TLS_CMD"
$redis_base_cmd ${KB_ACCOUNT_STATEMENT}
$redis_base_cmd acl save
