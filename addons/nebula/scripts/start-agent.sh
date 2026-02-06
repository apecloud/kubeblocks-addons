#!/bin/bash
set -ex
# start logrotate
sh /scripts/logrotate.sh
cron -l 2

if [ -f "/usr/local/nebula/logs/.kb_restore" ]; then
  while true; do
    # start restore-agent
    pid=`ps -eo pid,args | grep -F "restore-agent" | grep -v "grep" | tail -1 | awk '{print $1}'`
    if [ -z "$pid" ]; then
      echo "restore-agent is not running, start it now."  >> /tmp/restore-agent.log
      /usr/local/bin/restore-agent &
    fi
    sleep 5
    # check if restoration is completed
    if [ ! -f "/usr/local/nebula/logs/.kb_restore" ] && [ ! -f "/usr/local/nebula/logs/.kb_agent" ]; then
      echo "$(date): Nebula restoration completed."
      break
    fi
    pid=`ps -eo pid,args | grep -F "restore-agent" | grep -v "grep" | tail -1 | awk '{print $1}'`
    if [ -z "$pid" ]; then
      echo "restore-agent is not running, exit..."
      exit 1
    fi
    echo "$(date): Waiting for Nebula restoration to complete..."
  done
  # kill restore-agent if it is still running
  pid=`ps -eo pid,args | grep -F "restore-agent" | grep -v "grep" | tail -1 | awk '{print $1}'`
  if [ -n "$pid" ]; then
    echo "restore-agent is not running, start it now."  >> /tmp/restore-agent.log
    kill $pid
  fi
fi

# start agent
meta_ep=$(echo $NEBULA_METAD_SVC | cut -d',' -f1 | cut -d':' -f1)
until curl -L  http://${meta_ep}:19559/status; do sleep 5; done
exec /usr/local/bin/agent  --agent="${POD_FQDN}:8888" --meta="${meta_ep}:9559" --ratelimit=${RATE_LIMIT}
