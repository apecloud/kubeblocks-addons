#!/bin/bash
set -exo pipefail

# shellcheck disable=SC1091
. "/scripts/common.sh"

member_leave_diagnose_not_ready() {
  local phase="$1"
  local context="$2"
  local retry_safe="$3"

  {
    echo "memberLeave diagnosis:"
    echo "  action: memberLeave"
    echo "  phase: ${phase}"
    echo "${context}"
    echo "  next-retry-safe: ${retry_safe}"
  } >&2
}

validate_member_leave_inputs() {
  local missing=""
  local context

  [ -n "${KB_LEAVE_MEMBER_POD_NAME:-}" ] || missing="${missing} KB_LEAVE_MEMBER_POD_NAME"
  [ -n "${KB_LEAVE_MEMBER_POD_FQDN:-}" ] || missing="${missing} KB_LEAVE_MEMBER_POD_FQDN"

  if [ -n "$missing" ]; then
    context=$(printf '  missing-inputs:%s' "$missing")
    member_leave_diagnose_not_ready "required-input-empty" "$context" "no"
    return 1
  fi
}

find_leave_target_id() {
  local target_name="$1"

  awk -v target_name="$target_name" '
    function field_value(line, value) {
      value = line
      sub(/^[^:]*:[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      sub(/^"/, "", value)
      sub(/"$/, "", value)
      return value
    }
    function clear_block() {
      in_member = 0
      member_id = ""
      member_name = ""
      id_seen = 0
      name_seen = 0
      peer_count = 0
    }
    function finish_member() {
      if (!in_member) return
      if (id_seen != 1 || name_seen != 1 || peer_count < 1) malformed = 1
      if (member_name == target_name) {
        if (++target_count != 1) malformed = 1
        target_id = member_id
      }
      clear_block()
    }
    /^"ID"[[:space:]]*:/ {
      finish_member()
      in_member = 1
      saw_member = 1
      if ($0 !~ /^"ID"[[:space:]]*:[[:space:]]*[0-9]+[[:space:]]*$/) {
        malformed = 1
      } else {
        member_id = field_value($0)
        if (member_ids["id:" member_id]++) malformed = 1
        id_seen = 1
      }
      next
    }
    /^[[:space:]]*$/ { finish_member(); next }
    /^"Name"[[:space:]]*:/ {
      if (!in_member || name_seen ||
          $0 !~ /^"Name"[[:space:]]*:[[:space:]]*"[^"]*"[[:space:]]*$/) {
        malformed = 1
      } else {
        member_name = field_value($0)
        if (member_name != "" && member_names[member_name]++) malformed = 1
        name_seen = 1
      }
      next
    }
    /^"PeerURL"[[:space:]]*:/ {
      if (!in_member ||
          $0 !~ /^"PeerURL"[[:space:]]*:[[:space:]]*"[^"]+"[[:space:]]*$/) {
        malformed = 1
      } else {
        peer_count++
      }
      next
    }
    END {
      finish_member()
      if (!saw_member || malformed) exit 2
      if (target_count == 0) print "absent"
      else print target_id
    }
  '
}

validate_leave_snapshot() {
  local member_list="$1"
  local target_name="$2"
  local client_protocol="$3"
  local peer_protocol="$4"
  local context="$5"
  local target_id

  if ! printf '%s\n' "$member_list" | \
    build_current_contact_candidates "" "$client_protocol" "" \
      "validate-only" "$peer_protocol" >/dev/null; then
    member_leave_diagnose_not_ready "member-list-invalid" "$context" "no"
    return 1
  fi

  if ! target_id=$(printf '%s\n' "$member_list" | find_leave_target_id "$target_name"); then
    member_leave_diagnose_not_ready "member-list-invalid" "$context" "no"
    return 1
  fi

  printf '%s\n' "$target_id"
}

build_leave_contacts() {
  local member_list="$1"
  local target_id="$2"
  local client_protocol="$3"
  local peer_protocol="$4"
  local context="$5"
  local contacts rc

  if contacts=$(printf '%s\n' "$member_list" | \
    build_current_contact_candidates "" "$client_protocol" "$target_id" \
      "contacts" "$peer_protocol"); then
    printf '%s\n' "$contacts"
    return 0
  else
    rc=$?
  fi

  case "$rc" in
    2)
      member_leave_diagnose_not_ready "member-list-invalid" "$context" "no"
      ;;
    3)
      member_leave_diagnose_not_ready "contact-candidate-over-limit" "$context" "no"
      ;;
    4)
      member_leave_diagnose_not_ready "contact-candidate-empty" "$context" "yes"
      ;;
    *)
      member_leave_diagnose_not_ready "contact-candidate-build-failed" "$context" "no"
      ;;
  esac
  return 1
}

member_leave() {
  local local_endpoint="127.0.0.1:2379"
  local client_protocol peer_protocol member_list target_id target_id_hex contacts context remove_rc

  validate_member_leave_inputs || return 1

  context=$(printf '  member: %s\n  member-fqdn: %s' \
    "$KB_LEAVE_MEMBER_POD_NAME" "$KB_LEAVE_MEMBER_POD_FQDN")
  if ! validate_local_leader "$local_endpoint"; then
    member_leave_diagnose_not_ready "selected-contact-not-current-leader" "$context" "yes"
    return 1
  fi

  client_protocol=$(get_protocol "advertise-client-urls")
  peer_protocol=$(get_protocol "initial-advertise-peer-urls")
  if ! member_list=$(exec_bounded_etcdctl "$local_endpoint" member list -w fields); then
    member_leave_diagnose_not_ready "member-list-query-failed" "$context" "yes"
    return 1
  fi
  target_id=$(validate_leave_snapshot "$member_list" "$KB_LEAVE_MEMBER_POD_NAME" \
    "$client_protocol" "$peer_protocol" "$context") || return 1

  if [ "$target_id" = "absent" ]; then
    log "Member $KB_LEAVE_MEMBER_POD_NAME already absent from cluster"
    return 0
  fi

  context=$(printf '  member: %s\n  member-id: %s' "$KB_LEAVE_MEMBER_POD_NAME" "$target_id")
  contacts=$(build_leave_contacts "$member_list" "$target_id" \
    "$client_protocol" "$peer_protocol" "$context") || return 1
  if ! target_id_hex=$(printf '%x' "$target_id"); then
    member_leave_diagnose_not_ready "member-id-invalid" "$context" "no"
    return 1
  fi

  log "Removing member $target_id_hex via current contacts $contacts"
  if exec_bounded_etcdctl "$contacts" member remove "$target_id_hex"; then
    remove_rc=0
  else
    remove_rc=$?
  fi

  context=$(printf '  member: %s\n  member-id: %s\n  member-remove-rc: %s' \
    "$KB_LEAVE_MEMBER_POD_NAME" "$target_id" "$remove_rc")
  if ! member_list=$(exec_bounded_etcdctl "$contacts" member list -w fields); then
    member_leave_diagnose_not_ready "member-post-remove-query-failed" "$context" "yes"
    return 1
  fi
  target_id=$(validate_leave_snapshot "$member_list" "$KB_LEAVE_MEMBER_POD_NAME" \
    "$client_protocol" "$peer_protocol" "$context") || return 1

  if [ "$target_id" = "absent" ]; then
    log "Member $KB_LEAVE_MEMBER_POD_NAME left cluster"
    return 0
  fi

  if [ "$remove_rc" -eq 0 ]; then
    member_leave_diagnose_not_ready "member-removal-not-observed" "$context" "yes"
  else
    member_leave_diagnose_not_ready "member-remove-failed" "$context" "yes"
  fi
  return 1
}

# Shellspec magic
setup_shellspec

# main
load_common_library
member_leave
