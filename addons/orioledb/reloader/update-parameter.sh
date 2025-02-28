#!/bin/sh
set -e

do_reload() {
    if [ -z "$1" ]; then
        echo "missing param name" >&2
        return 1
    fi
    if [ -z "$2" ]; then
        echo "missing value" >&2
        return 1
    fi

    paramName="$1"
    paramValue="$2"

    PGPASSWORD=${POSTGRES_PASSWORD} psql -h localhost -U "${POSTGRES_USER}" -c "alter system set ${paramName}='${paramValue}'"
    PGPASSWORD=${POSTGRES_PASSWORD} psql -h localhost -U "${POSTGRES_USER}" -c "select pg_reload_conf()"
}

# if test by shell spec include, just return 0
if [ "${__SOURCED__:+x}" ]; then
  return 0
fi

do_reload "$@"

