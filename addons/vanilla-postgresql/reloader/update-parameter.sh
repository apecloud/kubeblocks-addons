#!/bin/sh
set -e

paramName="${1:?missing param name}"
paramValue="${2:?missing value}"

PGPASSWORD=${POSTGRES_PASSWORD} psql -h localhost -U "${POSTGRES_USER}" -c "alter system set ${paramName}='${paramValue}'"
PGPASSWORD=${POSTGRES_PASSWORD} psql -h localhost -U "${POSTGRES_USER}" -c "select pg_reload_conf()"