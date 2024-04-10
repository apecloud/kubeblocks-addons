#!/usr/bin/env bash
set -eu

while [[ $(grep -Exc $HOSTNAME /mnt/elastic-internal/scripts/suspended_pods.txt) -eq 1 ]]; do
    echo Pod suspended via eck.k8s.elastic.co/suspend annotation
    sleep 10
done