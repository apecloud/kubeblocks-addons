#!/bin/sh

if [ "$POSTGRES_PRIMARY_POD_NAME" != "$KB_SWITCHOVER_CURRENT_NAME" ]; then
  echo "switchover action not triggered for primary pod. Exiting."
  exit 0
fi

/tools/syncerctl switchover --primary "$POSTGRES_PRIMARY_POD_NAME" ${KB_SWITCHOVER_CANDIDATE_NAME:+--candidate "$KB_SWITCHOVER_CANDIDATE_NAME"}
