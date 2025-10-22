#!/bin/sh

res=$(curl http://localhost:8091)
me=$(echo "$res" | jq '.httpAddr' -r)
leader=$(echo "$res" | jq '.leader' -r)
if [ "$me" = "$leader" ]; then
    echo "leader"
else
    echo "follower"
fi
