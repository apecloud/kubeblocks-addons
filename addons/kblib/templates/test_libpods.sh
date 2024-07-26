#!/bin/bash

source "./test_utils.sh"

## TODO: We should not redefine the function here.

getPodListFromEnv() {
  local envName="${1:-KB_POD_LIST}"

  # Check if the environment variable exists
  if [[ -z "${!envName}" ]]; then
    echo "failed to get pod list cause environment variable '$envName' does not exist" >&2
    return 1
  fi

  local podListStr="${!envName}"
  local podList=()

  IFS=',' read -ra podList <<< "$podListStr"

  echo "${podList[@]}"
}

minLexicographicalOrderPod() {
  local podListStr="${1:-${KB_POD_LIST}}"
  local podList=()

  IFS=',' read -ra podList <<< "$podListStr"

  local minimumPod="${podList[0]}"
  for pod in "${podList[@]}"; do
    if [[ "$pod" < "$minimumPod" ]]; then
      minimumPod="$pod"
    fi
  done

  echo "$minimumPod"
}

# Tests defined below

test_getPodListFromEnv() {
  local test_case=$1
  local result

  getPodListFromEnv ""
  assert_false $? "$test_case (non-existing default KB_POD_LIST env)"

  export TEST_POD_LIST="pod1,pod2,pod3"
  export KB_POD_LIST="kb_pod1,kb_pod2,kb_pod3"

  result=$(getPodListFromEnv "TEST_POD_LIST")
  assert_equal "$result" "pod1 pod2 pod3" "$test_case (existing provided env)"

  result=$(getPodListFromEnv "")
  assert_equal "$result" "kb_pod1 kb_pod2 kb_pod3" "$test_case (existing default KB_POD_LIST env)"

  getPodListFromEnv "NON_EXISTENT_ENV"
  assert_false $? "$test_case (non-existing default KB_POD_LIST env)"

  unset TEST_POD_LIST
  unset KB_POD_LIST
}

test_minLexicographicalOrderPod() {
  local test_case=$1
  local result

  export KB_POD_LIST="pod3,pod2,pod1"

  result=$(minLexicographicalOrderPod "pod2,pod1,pod3")
  assert_equal "$result" "pod1" "$test_case (explicit pod list)"

  result=$(minLexicographicalOrderPod "")
  assert_equal "$result" "pod1" "$test_case (default pod list)"

  result=$(minLexicographicalOrderPod "pod-pod-0,pod-1,pod-pod-1")
  assert_equal "$result" "pod-1" "$test_case (complex pod names 1)"

  result=$(minLexicographicalOrderPod "pod-0,pod-0-0,pod-1-0")
  assert_equal "$result" "pod-0" "$test_case (complex pod names 2)"

  unset KB_POD_LIST
}

run_all_tests() {
  run_test test_getPodListFromEnv "kblib.pods.getPodListFromEnv"
  run_test test_minLexicographicalOrderPod "kblib.pods.minLexicographicalOrderPod"
}

# main run all tests
run_all_tests