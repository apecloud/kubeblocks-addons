#!/bin/bash

source "./test_utils.sh"

split() {
  local string="$1"
  local separator="${2:-,}"
  local array=()

  IFS="$separator" read -ra array <<< "$string"

  echo "${array[@]}"
}

contains() {
  local string="$1"
  local substring="$2"

  if [[ "$string" == *"$substring"* ]]; then
    return 0
  else
    return 1
  fi
}

hasPrefix() {
  local string="$1"
  local prefix="$2"

  if [[ "$string" == "$prefix"* ]]; then
    return 0
  else
    return 1
  fi
}

hasSuffix() {
  local string="$1"
  local suffix="$2"

  if [[ "$string" == *"$suffix" ]]; then
    return 0
  else
    return 1
  fi
}

replace() {
  local string="$1"
  local old="$2"
  local new="$3"
  local n=$4

  if [[ -z "$old" ]]; then
    echo "$string"
    return
  fi

  local count=0
  local result=""

  while [[ "$string" == *"$old"* && (n -lt 0 || count -lt n) ]]; do
    local index=${string%%$old*}
    result+="${index}${new}"
    string="${string#*$old}"
    ((count++))
  done

  result+="$string"
  echo "$result"
}

replaceAll() {
  local string="$1"
  local old="$2"
  local new="$3"

  if [[ -z "$old" ]]; then
    echo "$string"
    return
  fi

  echo "${string//$old/$new}"
}

test_split() {
  local test_case=$1
  local result
  result=$(split "a,b,c")
  assert_equal "$result" "a b c" "$test_case (default separator)"

  result=$(split "a-b-c" "-")
  assert_equal "$result" "a b c" "$test_case (custom separator)"
}

test_contains() {
  local test_case=$1
  contains "hello world" "world"
  assert_true $? "$test_case (contains)"

  contains "hello world" "foo"
  assert_false $? "$test_case (not contains)"
}

test_hasPrefix() {
  local test_case=$1
  hasPrefix "hello world" "hello"
  assert_true $? "$test_case (has prefix)"

  hasPrefix "hello world" "world"
  assert_false $? "$test_case (no prefix)"
}

test_hasSuffix() {
  local test_case=$1
  hasSuffix "hello world" "world"
  assert_true $? "$test_case (has suffix)"

  hasSuffix "hello world" "hello"
  assert_false $? "$test_case (no suffix)"
}

test_replace() {
  local test_case=$1
  local result
  result=$(replace "hello world hello" "hello" "hi" 1)
  assert_equal "$result" "hi world hello" "$test_case (replace single)"

  result=$(replace "hello world hello" "hello" "hi" 2)
  assert_equal "$result" "hi world hi" "$test_case (replace multiple)"

  result=$(replace "hello world hello" "hello" "hi" -1)
  assert_equal "$result" "hi world hi" "$test_case (replace with index -1)"
}

test_replaceAll() {
  local test_case=$1
  local result
  result=$(replaceAll "hello world hello" "hello" "hi")
  assert_equal "$result" "hi world hi" "$test_case (replace all)"
}

run_all_tests() {
  run_test test_split "strings.split"

  run_test test_contains "strings.contains"

  run_test test_hasPrefix "strings.hasPrefix"

  run_test test_hasSuffix "strings.hasSuffix"

  run_test test_replace "strings.replace"

  run_test test_replaceAll "strings.replaceAll"
}

# main run All tests
run_all_tests