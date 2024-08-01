#!/bin/bash

convert_tpl_to_bash() {
  local input_file="$1"
  local output_file="$2"

  sed -e '/^{{\/\*$/,/^\*\/}}$/d' \
      -e '/^{{-.*}}/d' \
      -e 's/{{- define ".*" }}//' \
      -e 's/{{- end }}//' \
      "$input_file" > "$output_file"
  echo "Converted $input_file to $output_file successfully"
}

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

assert_result_contains() {
  local error_output=$1
  local expected_substring=$2
  local test_case=$3

  if [[ "$error_output" == *"$expected_substring"* ]]; then
    echo "Passed: Test case '$test_case' passed: error contains expected substring"
  else
    echo "Error: Test case '$test_case' failed: error does not contain expected substring"
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