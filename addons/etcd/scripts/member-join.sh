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

    function canonical_host(host, parts, count, i, result) {
      sub(/[.]$/, "", host)
      host = tolower(host)
      if (host == "" || length(host) > 253) return ""
      if (host ~ /^[0-9.]+$/) {
        count = split(host, parts, ".")
        if (count != 4) return ""
        result = ""
        for (i = 1; i <= 4; i++) {
          if (parts[i] !~ /^[0-9]+$/ || parts[i] + 0 > 255) return ""
          result = result (i == 1 ? "" : ".") (parts[i] + 0)
        }
        return result
      }
      count = split(host, parts, ".")
      for (i = 1; i <= count; i++) {
        if (length(parts[i]) < 1 || length(parts[i]) > 63 ||
            parts[i] !~ /^[a-z0-9][a-z0-9-]*$/ || parts[i] ~ /-$/) return ""
      }
      return host
    }

    function canonical_peer_url(value, required_protocol, marker, rest, host, port, protocol) {
      marker = index(value, "://")
      if (marker == 0) return ""
      protocol = substr(value, 1, marker - 1)
      rest = substr(value, marker + 3)
      if (protocol != required_protocol || rest !~ /:[0-9]+$/) return ""
      port = rest
      sub(/^.*:/, "", port)
      if (port !~ /^[1-9][0-9]*$/ || port + 0 > 65535) return ""
      host = rest
      sub(/:[0-9]+$/, "", host)
      host = canonical_host(host)
      if (host == "") return ""
      return protocol "://" host ":" port
    }

    BEGIN {
      target_protocol = target_peer_url
      sub(/:.*/, "", target_protocol)
      if (target_protocol != "http" && target_protocol != "https") malformed = 1
      canonical_target_peer_url = canonical_peer_url(target_peer_url, target_protocol)
      if (canonical_target_peer_url == "") malformed = 1
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
      peer_url = ""
      if (!in_member ||
          $0 !~ /^"PeerURL"[[:space:]]*:[[:space:]]*"[^"]+"[[:space:]]*$/) {
        malformed = 1
        next
      }
      peer_url = canonical_peer_url(field_value($0), target_protocol)
      if (peer_url == "") {
        malformed = 1
        next
      }
      peer_seen = 1
      if (peer_url == canonical_target_peer_url) {
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

validate_member_join_inputs() {
  local missing=""
  local context

  [ -n "${KB_JOIN_MEMBER_POD_NAME:-}" ] || missing="${missing} KB_JOIN_MEMBER_POD_NAME"
  [ -n "${KB_JOIN_MEMBER_POD_FQDN:-}" ] || missing="${missing} KB_JOIN_MEMBER_POD_FQDN"

  if [ -n "$missing" ]; then
    context=$(printf '  missing-inputs:%s' "$missing")
    member_join_diagnose_not_ready "required-input-empty" "$context" "no"
    return 1
  fi
}

build_join_contacts() {
  local member_list="$1"
  local target_name="$2"
  local client_protocol="$3"
  local peer_protocol="$4"
  local context="$5"
  local contacts rc

  if contacts=$(printf '%s\n' "$member_list" | \
    build_current_contact_candidates "$target_name" "$client_protocol" "" "contacts" "$peer_protocol"); then
    printf '%s\n' "$contacts"
    return 0
  else
    rc=$?
  fi

  case "$rc" in
    2)
      member_join_diagnose_not_ready "member-list-invalid" "$context" "no"
      ;;
    3)
      member_join_diagnose_not_ready "contact-candidate-over-limit" "$context" "no"
      ;;
    4)
      member_join_diagnose_not_ready "contact-candidate-empty" "$context" "yes"
      ;;
    *)
      member_join_diagnose_not_ready "contact-candidate-build-failed" "$context" "no"
      ;;
  esac
  return 1
}

classify_join_snapshot() {
  local member_list="$1"
  local target_name="$2"
  local target_peer_url="$3"
  printf '%s\n' "$member_list" | classify_member_state "$target_name" "$target_peer_url"
}

validate_join_snapshot() {
  local member_list="$1"
  local client_protocol="$2"
  local peer_protocol="$3"
  local context="$4"

  if ! printf '%s\n' "$member_list" | \
    build_current_contact_candidates "" "$client_protocol" "" \
      "validate-only" "$peer_protocol" >/dev/null; then
    member_join_diagnose_not_ready "member-list-invalid" "$context" "no"
    return 1
  fi
}

has_target_contact_collision() {
  local target_host="$1"
  local contacts="$2"

  printf '%s\n' "$contacts" | awk -v target_host="$target_host" '
    {
      count = split($0, values, ",")
      for (i = 1; i <= count; i++) {
        host = values[i]
        sub(/^[^:]+:\/\//, "", host)
        sub(/:[0-9]+$/, "", host)
        if (host == target_host) found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  '
}

add_member() {
  local local_endpoint="127.0.0.1:2379"
  local join_member_endpoint peer_protocol client_protocol target_peer_url
  local member_list contacts member_state context add_rc

  validate_member_join_inputs || return 1

  context=$(printf '  member: %s\n  member-fqdn: %s' \
    "$KB_JOIN_MEMBER_POD_NAME" "$KB_JOIN_MEMBER_POD_FQDN")
  if ! validate_local_leader "$local_endpoint"; then
    member_join_diagnose_not_ready "selected-contact-not-current-leader" "$context" "yes"
    return 1
  fi

  if ! join_member_endpoint=$(get_endpoint_adapt_lb \
    "${PEER_ENDPOINT:-}" "$KB_JOIN_MEMBER_POD_NAME" "$KB_JOIN_MEMBER_POD_FQDN"); then
    member_join_diagnose_not_ready "target-endpoint-invalid" "$context" "no"
    return 1
  fi
  peer_protocol=$(get_protocol "initial-advertise-peer-urls")
  client_protocol=$(get_protocol "advertise-client-urls")
  target_peer_url="$peer_protocol://$join_member_endpoint:2380"

  context=$(printf '  member: %s\n  peer-url: %s' "$KB_JOIN_MEMBER_POD_NAME" "$target_peer_url")

  if ! member_list=$(exec_bounded_etcdctl "$local_endpoint" member list -w fields); then
    member_join_diagnose_not_ready "member-list-query-failed" "$context" "yes"
    return 1
  fi
  validate_join_snapshot "$member_list" "$client_protocol" "$peer_protocol" \
    "$context" || return 1
  if ! member_state=$(classify_join_snapshot "$member_list" \
    "$KB_JOIN_MEMBER_POD_NAME" "$target_peer_url"); then
    member_join_diagnose_not_ready "member-list-invalid" "$context" "no"
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

  contacts=$(build_join_contacts "$member_list" "$KB_JOIN_MEMBER_POD_NAME" \
    "$client_protocol" "$peer_protocol" "$context") || return 1
  if has_target_contact_collision "$join_member_endpoint" "$contacts"; then
    member_join_diagnose_not_ready "target-address-collision" "$context" "no"
    return 1
  fi

  log "Adding member $KB_JOIN_MEMBER_POD_NAME via current contacts $contacts"
  log "Join member peer URL: $target_peer_url"

  if exec_bounded_etcdctl "$contacts" member add "$KB_JOIN_MEMBER_POD_NAME" --peer-urls="$target_peer_url"; then
    add_rc=0
  else
    add_rc=$?
  fi

  context=$(printf '  member: %s\n  peer-url: %s\n  member-add-rc: %s' \
    "$KB_JOIN_MEMBER_POD_NAME" "$target_peer_url" "$add_rc")

  if ! member_list=$(exec_bounded_etcdctl "$contacts" member list -w fields); then
    member_join_diagnose_not_ready "member-post-add-query-failed" "$context" "yes"
    return 1
  fi
  validate_join_snapshot "$member_list" "$client_protocol" "$peer_protocol" \
    "$context" || return 1
  if ! member_state=$(classify_join_snapshot "$member_list" \
    "$KB_JOIN_MEMBER_POD_NAME" "$target_peer_url"); then
    member_join_diagnose_not_ready "member-list-invalid" "$context" "no"
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
