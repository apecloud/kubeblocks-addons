#!/bin/bash

set -e

replicas=$(echo "${POD_FQDN_LIST}" | tr ',' '\n')
for replica in $replicas; do
    influxd-ctl -bind "$META_ADDRESS" "$replica:8088"
done
