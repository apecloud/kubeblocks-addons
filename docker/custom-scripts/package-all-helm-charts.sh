#!/usr/bin/env bash
#
# This script will package all addons helm charts.
#
# Syntax: ./package-all-helm-charts.sh TARGET_DIR

set -e

if [ $# -ne 1 ]; then
  echo "Syntax: ./package-all-helm-charts.sh TARGET_DIR"
  exit 1
fi

TARGET_DIR=${1:-"charts"}

package_helm_charts() {
    if [[ ! -d addons ]]; then
        echo "not found addons dir"
        exit 1
    fi
    for chartName in $(ls addons); do
        if [[ "$chartName" == *"-cluster" ]]; then
            continue
        fi
        chartDir="addons/${chartName}"
        if [[ -d ${chartDir} ]]; then
            echo "helm package ${chartName}"
            helm package ${chartDir} --destination "${TARGET_DIR}" --dependency-update
        fi
    done
}

# make directories
mkdir -p "${TARGET_DIR}"

package_helm_charts
