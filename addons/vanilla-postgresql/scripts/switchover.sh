#!/bin/sh

/tools/syncerctl switchover --primary "$POSTGRES_PRIMARY_POD_NAME" ${KB_SWITCHOVER_CANDIDATE_NAME:+--candidate "$KB_SWITCHOVER_CANDIDATE_NAME"}
