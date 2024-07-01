#!/bin/sh
if [ -n "${metadataStoreUrl}" ]; then
  echo "waiting for zookeeper:{${metadataStoreUrl} to be ready..."
  zkDomain="${metadataStoreUrl%%:*}"
  until echo ruok | nc -q 1 ${zkDomain} 2181 | grep imok; do
    sleep 1;
  done;
  echo "zk is ready..."
fi