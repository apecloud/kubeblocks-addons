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
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -eo pipefail".
    set -eo pipefail;
}

http () {
    local path="${1}"
    if [ -n "${USERNAME}" ] && [ -n "${PASSWORD}" ]; then
        BASIC_AUTH="-u ${USERNAME}:${PASSWORD}"
    else
        BASIC_AUTH=''
    fi
    curl -XGET -s -k --fail ${BASIC_AUTH} https://${CLUSTER_NAME}-${OPENSEARCH_COMPONENT_SHORT_NAME}-headless:9200:${path}
}

cleanup () {
    while true ; do
    local master="$(http "/_cat/master?h=node" || echo "")"
    if [[ $master == "${CLUSTER_NAME}-${OPENSEARCH_COMPONENT_SHORT_NAME}"* && $master != "${NODE_NAME}" ]]; then
        echo "This node is not master."
        break
    fi
    echo "This node is still master, waiting gracefully for it to step down"
    sleep 1
    done

    if [ "false" == "$ut_mode" ]; then
        exit 0
    fi
}

trap cleanup SIGTERM

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

sleep infinity &
wait $!