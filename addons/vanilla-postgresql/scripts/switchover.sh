#!/bin/sh

switchover() {
  if [ "$POSTGRES_PRIMARY_POD_NAME" != "$KB_SWITCHOVER_CURRENT_NAME" ]; then
    echo "switchover action not triggered for primary pod. Exiting."
    exit 0
  fi

  cmd="/tools/dbctl"
  base_args="'--config-path' '/tools/config/dbctl/components' 'postgresql' 'switchover' '--primary' '${POSTGRES_PRIMARY_POD_NAME}'"

  if [ -n "$KB_SWITCHOVER_CANDIDATE_NAME" ]; then
    args="$base_args '--candidate' '${KB_SWITCHOVER_CANDIDATE_NAME}'"
  else
    args="$base_args"
  fi

  eval "$cmd $args"
}

switchover
