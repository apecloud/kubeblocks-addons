#!/bin/sh

set -e

replicas=$(echo "${POD_FQDN_LIST}" | tr ',' '\n')
for replica in $replicas; do
    /tools/influxd-ctl add-meta "$replica:8091"
done
