#!/bin/bash

set -e

replicas=$(echo "${POD_FQDN_LIST}" | tr ',' '\n')
for replica in $replicas; do
    echo "$replica" 1>&2
    influxd-ctl add-meta "$replica:8091" 1>&2
done
