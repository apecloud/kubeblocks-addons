#!/bin/bash
#
# This script runs template-level unit tests for all Helm charts
# in the addons-cluster directory that have a tests/pass or tests/fail directory.

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PROJECT_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)
ADDONS_CLUSTER_DIR="${PROJECT_ROOT}/addons-cluster"
FAILURES=0
TOTAL_TESTS=0

echo "Starting Helm chart template tests..."
echo "====================================="

# Find all chart directories
for chart_dir in "${ADDONS_CLUSTER_DIR}"/*; do
    if [ -d "${chart_dir}" ]; then
        chart_name=$(basename "${chart_dir}")
        pass_dir="${chart_dir}/tests/pass"
        fail_dir="${chart_dir}/tests/fail"
        chart_yaml="${chart_dir}/Chart.yaml"

        has_pass_tests=false
        if [ -d "${pass_dir}" ] && [ -n "$(find "${pass_dir}" -maxdepth 1 -name '*.yaml' -print -quit)" ]; then
            has_pass_tests=true
        fi

        has_fail_tests=false
        if [ -d "${fail_dir}" ] && [ -n "$(find "${fail_dir}" -maxdepth 1 -name '*.yaml' -print -quit)" ]; then
            has_fail_tests=true
        fi

        if [ "$has_pass_tests" = true ] || [ "$has_fail_tests" = true ]; then
            echo -e "\n--- Testing Chart: ${chart_name} ---"

            # 1. Build dependencies if Chart.yaml has them
            if [ -f "${chart_yaml}" ] && grep -q "^dependencies:" "${chart_yaml}"; then
                echo "  - Running helm dependency build..."
                if ! helm dependency build "${chart_dir}" --skip-refresh; then
                    echo -e "  ${RED}[FAIL] Helm dependency build failed for ${chart_name}${NC}"
                    FAILURES=$((FAILURES + 1))
                    # Count all tests in this chart as failed since we can't proceed
                    PASS_TEST_COUNT=0
                    if [ "$has_pass_tests" = true ]; then
                        PASS_TEST_COUNT=$(find "${pass_dir}" -maxdepth 1 -name '*.yaml' | wc -l | tr -d ' ')
                    fi
                    FAIL_TEST_COUNT=0
                    if [ "$has_fail_tests" = true ]; then
                        FAIL_TEST_COUNT=$(find "${fail_dir}" -maxdepth 1 -name '*.yaml' | wc -l | tr -d ' ')
                    fi
                    CHART_TEST_COUNT=$((PASS_TEST_COUNT + FAIL_TEST_COUNT))
                    TOTAL_TESTS=$((TOTAL_TESTS + CHART_TEST_COUNT))
                    continue # Skip to the next chart
                else
                    echo "  [OK] Helm dependencies built"
                fi
            fi

            # 2. Lint the chart
            echo "  - Running helm lint..."
            if ! helm lint "${chart_dir}"; then
                echo -e "  ${RED}[FAIL] Helm lint failed for ${chart_name}${NC}"
                FAILURES=$((FAILURES + 1))
                # Count all tests in this chart as failed since we can't proceed
                PASS_TEST_COUNT=0
                if [ "$has_pass_tests" = true ]; then
                    PASS_TEST_COUNT=$(find "${pass_dir}" -maxdepth 1 -name '*.yaml' | wc -l | tr -d ' ')
                fi
                FAIL_TEST_COUNT=0
                if [ "$has_fail_tests" = true ]; then
                    FAIL_TEST_COUNT=$(find "${fail_dir}" -maxdepth 1 -name '*.yaml' | wc -l | tr -d ' ')
                fi
                CHART_TEST_COUNT=$((PASS_TEST_COUNT + FAIL_TEST_COUNT))
                TOTAL_TESTS=$((TOTAL_TESTS + CHART_TEST_COUNT))
                continue # Skip to the next chart
            else
                echo "  [OK] Helm lint passed"
            fi

            # 3. Loop through all passing test value files
            if [ "$has_pass_tests" = true ]; then
                echo "  - Running passing test cases..."
                for test_file in "${pass_dir}"/*.yaml; do
                    TOTAL_TESTS=$((TOTAL_TESTS + 1))
                    test_name=$(basename "${test_file}" .yaml)
                    if ! helm template "test" "${chart_dir}" --namespace "test-ns" --values "${test_file}" > /dev/null; then
                        echo -e "    ${RED}[FAIL] Expected pass, but failed: '${test_name}'${NC}"
                        FAILURES=$((FAILURES + 1))
                    else
                        echo -e "    ${GREEN}[OK] Test case '${test_name}' passed as expected${NC}"
                    fi
                done
            fi

            # 4. Loop through all failing test value files
            if [ "$has_fail_tests" = true ]; then
                echo "  - Running failing test cases..."
                for test_file in "${fail_dir}"/*.yaml; do
                    TOTAL_TESTS=$((TOTAL_TESTS + 1))
                    test_name=$(basename "${test_file}" .yaml)
                    if helm template "test" "${chart_dir}" --namespace "test-ns" --values "${test_file}" > /dev/null 2>&1; then
                        echo -e "    ${RED}[FAIL] Expected failure, but passed: '${test_name}'${NC}"
                        FAILURES=$((FAILURES + 1))
                    else
                        echo -e "    ${GREEN}[OK] Test case '${test_name}' failed as expected${NC}"
                    fi
                done
            fi
        else
            echo -e "\n--- Skipping Chart: ${chart_name} (no test files found) ---"
        fi
    fi
done

echo "====================================="
if [ "${FAILURES}" -gt 0 ]; then
    echo -e "${RED}${FAILURES}/${TOTAL_TESTS} test(s) failed.${NC}"
    exit 1
else
    echo -e "${GREEN}All ${TOTAL_TESTS} chart tests passed successfully.${NC}"
fi