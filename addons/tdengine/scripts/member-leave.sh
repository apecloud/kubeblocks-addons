#!/bin/bash
endpoint=$KB_LEAVE_MEMBER_POD_NAME.${TAOS_COMPONENT_NAME}-headless.${KB_NAMESPACE}.svc.${CLUSTER_DOMAIN}:${TAOS_SERVICE_PORT}
res=$(taos -p$TAOS_ROOT_PASSWORD -s "select id from information_schema.ins_dnodes where endpoint='${endpoint}'")
if [[ "$res" == *"Query OK, 0 row(s) in set"* ]]; then
  echo "No dnode found for endpoint $endpoint, nothing to do, exit 0"
  exit 0
elif [[ "$res" != *"Query OK, 1 row(s) in set"* ]]; then
  echo "Failed to query dnode id for endpoint $endpoint, res: $res"
  exit 1
fi
res=$(echo "$res" | tail -n 3 | head -n 1)
dnode_id=$(echo $res | tr -d '|' | xargs | tr -d '\n')
echo "start to drop dnode with id: $dnode_id"
res=$(taos -p$TAOS_ROOT_PASSWORD -s "drop dnode ${dnode_id}")
if [[ "$res" == *"Drop OK"* ]]; then
  echo "drop dnode success, dnode id: $dnode_id"
  exit 0
fi
exit 1