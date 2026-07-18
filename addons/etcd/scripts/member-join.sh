#!/bin/bash
set -exo pipefail

# shellcheck disable=SC1091
. "/scripts/common.sh"

member_join_diagnose_not_ready() {
  local phase="$1"
  local context="$2"
  local retry_safe="$3"

  {
    echo "memberJoin diagnosis:"
    echo "  action: memberJoin"
    echo "  phase: ${phase}"
    echo "${context}"
    echo "  next-retry-safe: ${retry_safe}"
  } >&2
}

classify_member_state() {
  local target_name="$1"
  local target_peer_url="$2"

  awk -v target_name="$target_name" -v target_peer_url="$target_peer_url" '
    function field_value(line, value) {
      value = line
      sub(/^[^:]*:[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      sub(/^"/, "", value)
      sub(/"$/, "", value)
      return value
    }

    function finish_member() {
      if (!in_member) {
        return
      }

      if (!name_seen || !peer_seen) {
        malformed = 1
      }

      if (member_name == target_name && !peer_matches) {
        name_conflict = 1
      }

      if (peer_matches) {
        if (member_name == target_name) {
          exact = 1
        } else if (member_name == "") {
          unstarted = 1
        } else {
          peer_conflict = 1
        }
      }

      in_member = 0
      member_name = ""
      name_seen = 0
      peer_seen = 0
      peer_matches = 0
    }

    /^"ID"[[:space:]]*:/ {
      finish_member()
      in_member = 1
      saw_member = 1
      if ($0 !~ /^"ID"[[:space:]]*:[[:space:]]*[0-9]+[[:space:]]*$/) {
        malformed = 1
      }
      next
    }

    /^[[:space:]]*$/ {
      finish_member()
      next
    }

    /^"Name"[[:space:]]*:/ {
      if (!in_member || name_seen ||
          $0 !~ /^"Name"[[:space:]]*:[[:space:]]*"[^"]*"[[:space:]]*$/) {
        malformed = 1
        next
      }
      member_name = field_value($0)
      name_seen = 1
      next
    }

    /^"PeerURL"[[:space:]]*:/ {
      if (!in_member ||
          $0 !~ /^"PeerURL"[[:space:]]*:[[:space:]]*"[^"]*"[[:space:]]*$/) {
        malformed = 1
        next
      }
      peer_seen = 1
      if (field_value($0) == target_peer_url) {
        peer_matches = 1
      }
      next
    }

    END {
      finish_member()
      if (!saw_member || malformed) {
        exit 2
      } else if (name_conflict) {
        print "name-conflict"
      } else if (peer_conflict) {
        print "peer-conflict"
      } else if (exact) {
        print "exact"
      } else if (unstarted) {
        print "unstarted-registered"
      } else {
        print "absent"
      }
    }
  '
}

read_member_state() {
  local endpoint="$1"
  local target_name="$2"
  local target_peer_url="$3"
  local member_list

  if ! member_list=$(exec_etcdctl "$endpoint" member list -w fields); then
    return 1
  fi

  printf '%s\n' "$member_list" | classify_member_state "$target_name" "$target_peer_url"
}

validate_member_join_inputs() {
  local missing=""
  local context

  [ -n "${LEADER_POD_FQDN:-}" ] || missing="${missing} LEADER_POD_FQDN"
  [ -n "${KB_JOIN_MEMBER_POD_NAME:-}" ] || missing="${missing} KB_JOIN_MEMBER_POD_NAME"
  [ -n "${KB_JOIN_MEMBER_POD_FQDN:-}" ] || missing="${missing} KB_JOIN_MEMBER_POD_FQDN"

  if [ -n "$missing" ]; then
    context=$(printf '  missing-inputs:%s' "$missing")
    member_join_diagnose_not_ready "required-input-empty" "$context" "no"
    return 1
  fi
}

add_member() {
  local leader_pod_name leader_endpoint join_member_endpoint peer_protocol
  local target_peer_url member_state context add_rc

  validate_member_join_inputs || return 1

  leader_pod_name="${LEADER_POD_FQDN%%.*}"
  leader_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$leader_pod_name" "$LEADER_POD_FQDN")
  join_member_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$KB_JOIN_MEMBER_POD_NAME" "$KB_JOIN_MEMBER_POD_FQDN")
  peer_protocol=$(get_protocol "initial-advertise-peer-urls")
  target_peer_url="$peer_protocol://$join_member_endpoint:2380"

  context=$(printf '  member: %s\n  peer-url: %s' "$KB_JOIN_MEMBER_POD_NAME" "$target_peer_url")

  if ! member_state=$(read_member_state "$leader_endpoint:2379" "$KB_JOIN_MEMBER_POD_NAME" "$target_peer_url"); then
    member_join_diagnose_not_ready "member-list-query-failed" "$context" "yes"
    return 1
  fi

  case "$member_state" in
    exact)
      log "Member $KB_JOIN_MEMBER_POD_NAME already joined via $target_peer_url"
      return 0
      ;;
    unstarted-registered)
      log "Member $KB_JOIN_MEMBER_POD_NAME registered but not started via $target_peer_url"
      return 0
      ;;
    name-conflict)
      member_join_diagnose_not_ready "member-name-conflict" "$context" "no"
      return 1
      ;;
    peer-conflict)
      member_join_diagnose_not_ready "member-peer-url-conflict" "$context" "no"
      return 1
      ;;
    absent)
      ;;
    *)
      context=$(printf '%s\n  observed-state: %s' "$context" "$member_state")
      member_join_diagnose_not_ready "member-state-invalid" "$context" "no"
      return 1
      ;;
  esac

  log "Adding member $KB_JOIN_MEMBER_POD_NAME to cluster via leader $leader_endpoint"
  log "Join member peer URL: $target_peer_url"

  if exec_etcdctl "$leader_endpoint:2379" member add "$KB_JOIN_MEMBER_POD_NAME" --peer-urls="$target_peer_url"; then
    add_rc=0
  else
    add_rc=$?
  fi

  context=$(printf '  member: %s\n  peer-url: %s\n  member-add-rc: %s' \
    "$KB_JOIN_MEMBER_POD_NAME" "$target_peer_url" "$add_rc")

  if ! member_state=$(read_member_state "$leader_endpoint:2379" "$KB_JOIN_MEMBER_POD_NAME" "$target_peer_url"); then
    member_join_diagnose_not_ready "member-post-add-query-failed" "$context" "yes"
    return 1
  fi

  case "$member_state" in
    exact)
      log "Member $KB_JOIN_MEMBER_POD_NAME already joined via $target_peer_url"
      return 0
      ;;
    unstarted-registered)
      log "Member $KB_JOIN_MEMBER_POD_NAME registered but not started via $target_peer_url"
      return 0
      ;;
    name-conflict)
      member_join_diagnose_not_ready "member-name-conflict" "$context" "no"
      return 1
      ;;
    peer-conflict)
      member_join_diagnose_not_ready "member-peer-url-conflict" "$context" "no"
      return 1
      ;;
    absent)
      if [ "$add_rc" -eq 0 ]; then
        member_join_diagnose_not_ready "member-registration-not-observed" "$context" "yes"
      else
        member_join_diagnose_not_ready "member-add-failed" "$context" "yes"
      fi
      return 1
      ;;
    *)
      context=$(printf '%s\n  observed-state: %s' "$context" "$member_state")
      member_join_diagnose_not_ready "member-state-invalid" "$context" "no"
      return 1
      ;;
  esac
}

# Shellspec magic
setup_shellspec

# main
load_common_library
add_member
