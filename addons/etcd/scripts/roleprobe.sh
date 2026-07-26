#!/bin/bash

# shellcheck disable=SC1090,SC1091
roleprobe_script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "${roleprobe_script_dir}/common.sh"

parse_role_field() {
  local status="$1"
  local field_name="$2"
  local value_type="$3"

  printf '%s\n' "$status" | awk -v field_name="$field_name" -v value_type="$value_type" '
    BEGIN {
      key = "^[[:space:]]*\"" field_name "\"[[:space:]]*:"
      if (value_type == "id") {
        value = "[0-9]+"
      } else {
        value = "(true|false)"
      }
      valid = key "[[:space:]]*" value "[[:space:]]*$"
    }
    $0 ~ key {
      seen++
      if ($0 ~ valid) {
        parsed = $0
        sub(key "[[:space:]]*", "", parsed)
        sub("[[:space:]]*$", "", parsed)
        valid_count++
      }
    }
    END {
      if (seen != 1 || valid_count != 1) {
        exit 1
      }
      print parsed
    }
  '
}

get_etcd_role() {
  local status member_id leader_id is_learner
  if ! status=$(exec_etcdctl 127.0.0.1:2379 endpoint status -w fields --command-timeout=300ms --dial-timeout=100ms); then
    echo "ERROR: Failed to get endpoint status" >&2
    return 1
  fi

  if ! member_id=$(parse_role_field "$status" "MemberID" "id") ||
    ! leader_id=$(parse_role_field "$status" "Leader" "id") ||
    ! is_learner=$(parse_role_field "$status" "IsLearner" "bool"); then
    echo "ERROR: Failed to extract role fields from endpoint status" >&2
    return 1
  fi

  if [ "$member_id" = "$leader_id" ]; then
    echo "leader"
  elif [ "$is_learner" = "true" ]; then
    echo "learner"
  else
    echo "follower"
  fi
}

roleprobe_main() {
  local etcd_role
  if ! etcd_role=$(get_etcd_role); then
    return 1
  fi
  printf '%s' "$etcd_role"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  load_common_library
  roleprobe_main "$@"
fi
