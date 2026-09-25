#!/bin/sh
set -eu

DOLT_NO_DATABASE=true /scripts/doltdb-sql.sh "SELECT 1" >/dev/null
