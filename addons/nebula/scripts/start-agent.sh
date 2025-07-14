#!/bin/bash
set -ex
# start logrotate
sh /scripts/logrotate.sh
cron -l 2

if [ -f "/usr/local/nebula/logs/.kb_restore" ]; then
  while true; do
    sleep 5
    echo "$(date): Waiting for Nebula restoration to complete..."
  done
else
  # start agent
  meta_ep=$(echo $NEBULA_METAD_SVC | cut -d',' -f1 | cut -d':' -f1)
  until curl -L  http://${meta_ep}:19559/status; do sleep 5; done
  exec /usr/local/bin/agent  --agent="${POD_FQDN}:8888" --meta="${meta_ep}:9559" --ratelimit=${RATE_LIMIT}
fi
