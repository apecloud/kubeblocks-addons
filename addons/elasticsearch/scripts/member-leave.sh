#!/usr/bin/env bash

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

init_vars() {
  ENDPOINT="http://127.0.0.1:9200"
  CURL_OPTIONS="--fail --max-time 3 --retry 3"

  if [[ -z "${KB_LEAVE_MEMBER_POD_NAME}" ]]; then
    echo "KB_LEAVE_MEMBER_POD_NAME is not set, exiting"
    return 1
  fi
}

get_es_version() {
  local version_response
  local version

  if ! version_response=$(curl ${CURL_OPTIONS} -s "${ENDPOINT}"); then
    echo "failed to get es version"
    return 1
  fi

  version=$(echo "$version_response" | jq -r .version.number)
  echo "${version%.*}"
}

get_exclusion_url() {
  local version="$1"
  local url

  if awk "BEGIN {exit !($version < 7.8)}"; then
    url="${ENDPOINT}/_cluster/voting_config_exclusions/${KB_LEAVE_MEMBER_POD_NAME}"
  else
    url="${ENDPOINT}/_cluster/voting_config_exclusions?node_names=${KB_LEAVE_MEMBER_POD_NAME}"
  fi

  echo "$url"
}

clear_exclusions() {
  if ! curl ${CURL_OPTIONS} -X DELETE "${ENDPOINT}/_cluster/voting_config_exclusions?pretty&wait_for_removal=false"; then
    echo "failed to clear voting config exclusions"
    return 1
  fi
  echo "successfully cleared voting config exclusions"
}

add_node_to_exclusions() {
  local url="$1"

  if ! curl ${CURL_OPTIONS} -v -X POST "$url"; then
    echo "failed to add node ${KB_LEAVE_MEMBER_POD_NAME} to voting config exclusion list"
    echo "may be the voting config exclusion list is full, try to remove it first"
    clear_exclusions
    return 1
  fi

  echo "successfully added node ${KB_LEAVE_MEMBER_POD_NAME} to voting config exclusion list"
}

member_leave() {
  if ! init_vars; then
    exit 1
  fi

  echo "removing node ${KB_LEAVE_MEMBER_POD_NAME}"
  local version
  if ! version=$(get_es_version); then
    exit 1
  fi

  local exclusion_url
  exclusion_url=$(get_exclusion_url "$version")
  echo "exclusion url: $exclusion_url"

  if ! add_node_to_exclusions "$exclusion_url"; then
    exit 1
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
member_leave