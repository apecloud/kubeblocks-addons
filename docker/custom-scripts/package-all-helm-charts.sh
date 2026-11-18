#!/usr/bin/env bash
#
# This script will package all addons helm charts.
#
# Syntax: ./package-all-helm-charts.sh TARGET_DIR [PREBUILT_DIR]

set -e

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Syntax: ./package-all-helm-charts.sh TARGET_DIR [PREBUILT_DIR]"
  exit 1
fi

TARGET_DIR=${1:-"charts"}
PREBUILT_DIR=${2:-""}
PREBUILT_CHART_NAMES=""

load_prebuilt_charts() {
    if [[ -z "${PREBUILT_DIR}" || ! -d "${PREBUILT_DIR}" ]]; then
        return
    fi
    for chart_package in "${PREBUILT_DIR}"/*.tgz; do
        if [[ ! -f "${chart_package}" ]]; then
            continue
        fi
        cp "${chart_package}" "${TARGET_DIR}/"
    done
    if [[ -f "${PREBUILT_DIR}/.chart-names" ]]; then
        PREBUILT_CHART_NAMES=$(cat "${PREBUILT_DIR}/.chart-names")
    fi
}

is_prebuilt_chart() {
    local chart_name=${1:-}
    printf '%b' "${PREBUILT_CHART_NAMES}" | grep -Fxq "${chart_name}"
}

package_helm_charts() {
    if [[ ! -d addons ]]; then
        echo "not found addons dir"
        exit 1
    fi
    for chartDir in addons/*; do
        [[ -d ${chartDir} ]] || continue
        chartName=${chartDir##*/}
        if [[ "$chartName" == *"-cluster" ]]; then
            continue
        fi
        if [[ -n "${PREBUILT_CHART_NAMES}" ]]; then
            chart_name=$(awk -F': ' '$1 == "name" {print $2; exit}' "${chartDir}/Chart.yaml")
            if is_prebuilt_chart "${chart_name}"; then
                echo "use prebuilt chart ${chart_name}"
                continue
            fi
        fi
        echo "helm package ${chartName}"
        helm package "${chartDir}" --destination "${TARGET_DIR}" --dependency-update
    done
}

# make directories
mkdir -p "${TARGET_DIR}"

load_prebuilt_charts
package_helm_charts
