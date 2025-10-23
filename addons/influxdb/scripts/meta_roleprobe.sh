#!/bin/bash

set -e

export PATH="$PATH:/tools"

res=$(curl http://localhost:8091/status)
me=$(echo "$res" | jq '.raftAddr' -r)
leader=$(echo "$res" | jq '.leader' -r)
if [ "$me" = "$leader" ]; then
    echo "leader"
else
    echo "follower"
fi
