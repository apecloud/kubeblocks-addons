#!/bin/bash

source "./test_utils.sh"

## TODO: We should not redefine the function here.

envExist() {
  local envName="$1"

  if [[ -z "${!envName}" ]]; then
    echo "false, $envName does not exist"
    return 1
  fi

  echo "true, $envName exists"
  return 0
}

envsExist() {
  local envList=("$@")
  local missingEnvs=()

  for env in "${envList[@]}"; do
    if [[ -z "${!env}" ]]; then
      missingEnvs+=("$env")
    fi
  done

  if [[ ${#missingEnvs[@]} -eq 0 ]]; then
    echo "true, all environment variables exist"
    return 0
  else
    echo "false, the following environment variables do not exist: ${missingEnvs[*]}"
    return 1
  fi
}

# Tests defined below

test_envExist() {
  local test_case=$1
  local result

  export TEST_ENV="test_value"

  result=$(envExist "TEST_ENV")
  assert_equal "$result" "true, TEST_ENV exists" "$test_case (existing env)"

  result=$(envExist "NON_EXISTENT_ENV")
  assert_equal "$result" "false, NON_EXISTENT_ENV does not exist" "$test_case (non-existent env)"

  unset TEST_ENV
}

test_envsExist() {
  local test_case=$1
  local result

  export TEST_ENV1="test_value1"
  export TEST_ENV2="test_value2"

  result=$(envsExist "TEST_ENV1" "TEST_ENV2")
  assert_equal "$result" "true, all environment variables exist" "$test_case (all envs exist)"

  result=$(envsExist "TEST_ENV1" "NON_EXISTENT_ENV")
  assert_equal "$result" "false, the following environment variables do not exist: NON_EXISTENT_ENV" "$test_case (some envs do not exist)"

  unset TEST_ENV1
  unset TEST_ENV2
}

run_all_tests() {
  run_test test_envExist "envs.envExist"
  run_test test_envsExist "envs.envsExist"
}

# main run all tests
run_all_tests