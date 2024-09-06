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
  # when running in non-unit test mode, set the options "set -e".
  set -e;
}

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

acl_save_before_stop() {
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    acl_save_command="redis-cli -h 127.0.0.1 -p 6379 -a $REDIS_DEFAULT_PASSWORD acl save"
    logging_mask_acl_save_command="${acl_save_command/$REDIS_DEFAULT_PASSWORD/********}"
  else
    acl_save_command="redis-cli -h 127.0.0.1 -p 6379 acl save"
    logging_mask_acl_save_command="$acl_save_command"
  fi
  echo "acl save command: $logging_mask_acl_save_command"
  if output=$($acl_save_command 2>&1); then
    echo "acl save command executed successfully: $output"
  else
    echo "failed to execute acl save command: $output"
    exit 1
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
acl_save_before_stop
