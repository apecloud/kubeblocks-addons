#!/bin/bash

# This is magic for shellspec ut framework. "test" is a `test [expression]` well known as a shell command.
# Normally test without [expression] returns false. It means that __() { :; }
# function is defined if this script runs directly.
#
# shellspec overrides the test command and returns true *once*. It means that
# __() function defined internally by shellspec is called.
#
# In other words. If not in test mode, __ is just a comment. If test mode, __
# is a interception point.
#
# you should set ut_mode="true" when you want to run the script in shellspec file.
#
# shellcheck disable=SC2034
# shellcheck disable=SC2153
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

build_node_endpoint() {
  local service_port=${SERVICE_PORT:-6379}
  local node_endpoint="$CURRENT_POD_NAME.$CURRENT_SHARD_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN:$service_port"
  echo "$node_endpoint"
}

build_auth_args() {
  if [ -n "$REDIS_DEFAULT_PASSWORD" ]; then
    echo "-a $REDIS_DEFAULT_PASSWORD"
  fi
}

do_rebalance() {
  local node_endpoint="$1"
  local auth_args="$2"
  echo "rebalance redis cluster slots via node: $node_endpoint"
  # shellcheck disable=SC2086
  redis-cli $REDIS_CLI_TLS_CMD --cluster rebalance "$node_endpoint" --cluster-use-empty-masters --cluster-yes $auth_args
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
node_endpoint=$(build_node_endpoint)
auth_args=$(build_auth_args)
do_rebalance "$node_endpoint" "$auth_args"