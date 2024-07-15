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

echo "start config $KB_COMP_NAME..."

echo "configure ssh..."

cp /ssh-key/id_rsa /home/gbase/.ssh/id_rsa
cp /ssh-key/id_rsa.pub /home/gbase/.ssh/id_rsa.pub
cat /ssh-key/id_rsa.pub >> /home/gbase/.ssh/authorized_keys
chown -R gbase:gbase /home/gbase/.ssh
chmod 700 /home/gbase/.ssh
chmod 600 /home/gbase/.ssh/id_rsa /home/gbase/.ssh/authorized_keys

echo "complete ssh configure"

