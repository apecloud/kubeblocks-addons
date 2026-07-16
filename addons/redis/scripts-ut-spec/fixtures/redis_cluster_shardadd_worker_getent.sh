#!/usr/bin/env bash

set -u

if [ "${1:-}" = "ahostsv4" ] &&
   [ "${2:-}" = "redis-shard-new-headless.default.svc.cluster.local" ]; then
  printf '10.0.0.2 STREAM redis-shard-new-headless.default.svc.cluster.local\n'
  printf '10.0.0.2 DGRAM  redis-shard-new-headless.default.svc.cluster.local\n'
  exit 0
fi

exit 2
