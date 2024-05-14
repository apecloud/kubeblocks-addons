#!/bin/sh
set -ex

paramName="${1:?missing config}"
paramValue="${2:?missing value}"

psql -h 127.0.0.1 -c "alter system set ${paramName} = ${paramValue}"
psql -h 127.0.0.1 -c "select pg_reload_conf()"