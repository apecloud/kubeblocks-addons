#!/bin/sh
set -eu
# This endpoint has a flat JSON object with capitalized fields. The Go server
# omits IsLeader when false; an absent Leader means election is not complete.
unknown() { printf 'unknown\n'; exit 0; }
body=$(curl --silent --fail --connect-timeout 1 --max-time 2 \
  http://127.0.0.1:9333/cluster/status) || unknown
body=$(printf '%s' "$body" | tr -d '\n\r')
case "$body" in \{*\}) ;; *) unknown ;; esac
leader=$(printf '%s' "$body" | sed -n 's/.*"Leader"[[:space:]]*:[[:space:]]*"\([a-zA-Z0-9.:-]*\)".*/\1/p')
# ServerAddress JSON retains the optional gRPC port: host:9333[.grpcPort].
printf '%s\n' "$leader" | grep -Eq '^[a-zA-Z0-9.:-]+:9333(\.[0-9]+)?$' || unknown
if printf '%s' "$body" | grep -Eq '"IsLeader"[[:space:]]*:[[:space:]]*true[[:space:]]*[,}]'; then
  printf 'leader\n'
elif printf '%s' "$body" | grep -q '"IsLeader"'; then
  if printf '%s' "$body" | grep -Eq '"IsLeader"[[:space:]]*:[[:space:]]*false[[:space:]]*[,}]'; then
    printf 'follower\n'
  else
    unknown
  fi
else
  printf 'follower\n'
fi
