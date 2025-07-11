#!/bin/bash
set -ex
# start logrotate
sh /scripts/logrotate.sh
cron -l 2
# start agent
meta_ep=$(echo $NEBULA_METAD_SVC | cut -d',' -f1 | cut -d':' -f1)
until curl -L  http://${meta_ep}:19559/status; do sleep 5; done
exec /usr/local/bin/agent  --agent="${POD_FQDN}:8888" --meta="${meta_ep}:9559" --ratelimit=${RATE_LIMIT}