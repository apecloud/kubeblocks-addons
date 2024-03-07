#!/bin/sh
if [ -n "${metadataStoreUrl}" ]; then
  echo "waiting for zookeeper to be ready..."
  zkDomain="${metadataStoreUrl%%:*}"
  until echo ruok | nc -q 1 ${zkDomain} 2181 | grep imok; do
    sleep 1;
  done;
  echo "zk is ready..."
fi

if [ -n "${brokerSVC}" ]; then
  echo "waiting for broker to be ready..."
  while [ "$(curl -s -o /dev/null -w '%{http_code}' http://${brokerSVC}:80/status.html)" -ne "200" ]; do
    echo "pulsar cluster isn't initialized yet..."; sleep 1;
  done
fi