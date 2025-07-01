#!/bin/bash
endpoint=$KB_POD_FQDN.${CLUSTER_DOMAIN}:${TAOS_SERVICE_PORT}
res=$(taos -p$TAOS_ROOT_PASSWORD -s "select status from information_schema.ins_dnodes where endpoint='${endpoint}'")
if [[ "$res" != *"Query OK, 1 row(s) in set"* ]]; then
  echo "" | tr -d '\n'
  exit 0
fi
res=$(echo "$res" | tail -n 3 | head -n 1)
echo $res | tr -d '|' | xargs | tr -d '\n'