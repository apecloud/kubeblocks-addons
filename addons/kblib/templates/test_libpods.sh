#!/bin/bash

source "./test_utils.sh"

## TODO: We should not redefine the function here.

getPodList() {
  local podListStr="${1:-${KB_POD_LIST}}"
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

test_getPodList() {
  local test_case=$1
  local result

  export KB_POD_LIST="pod1,pod2,pod3"

  result=$(getPodList "pod1,pod2,pod3")
  assert_equal "$result" "pod1 pod2 pod3" "$test_case (explicit pod list)"

  result=$(getPodList "")
  assert_equal "$result" "pod1 pod2 pod3" "$test_case (default pod list)"

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
  run_test test_getPodList "kblib.pods.getPodList"
  run_test test_minLexicographicalOrderPod "kblib.pods.minLexicographicalOrderPod"
}

# main run all tests
run_all_tests