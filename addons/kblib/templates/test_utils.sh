#!/bin/bash

assert_equal() {
  local test_case=$3
  if [[ "$1" == "$2" ]]; then
    echo "Passed: Test case '$test_case' passed: $1 == $2"
  else
    echo "Error: Test case '$test_case' failed: $1 != $2, expected equal"
    return 1
  fi
}

assert_true() {
  local test_case=$2
  if [[ $1 -eq 0 ]]; then
    echo "Passed: Test case '$test_case' passed: true"
  else
    echo "Error: Test case '$test_case' failed: false, expected true"
    return 1
  fi
}

assert_false() {
  local test_case=$2
  if [[ $1 -ne 0 ]]; then
    echo "Passed: Test case '$test_case' passed: false"
  else
    echo "Error: Test case '$test_case' failed: true, expected false"
    return 1
  fi
}

run_test() {
  local test_func=$1
  local test_case=$2
  local failed=0

  echo "Running test case: $test_case"
  $test_func "$test_case"
  failed=$?
  echo "------------------------"

  return $failed
}