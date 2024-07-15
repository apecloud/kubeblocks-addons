#!/bin/bash

LOG_FILE="/config_${KB_CLUSTER_COMP_NAME}.log"

if [ ! -f "$LOG_FILE" ]; then
  touch "$LOG_FILE"
fi

exec > >(tee -a "$LOG_FILE") 2>&1

GLOBAL_OUTPUT=""

trap 'handle_error' ERR

handle_error() {
  echo "An error occurred in command: '$BASH_COMMAND'. Exiting..."
  echo "Command output: $GLOBAL_OUTPUT"
  exit 0
}

/scripts/set_ssh.sh

