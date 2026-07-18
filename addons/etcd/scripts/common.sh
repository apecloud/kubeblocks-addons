#!/var/run/etcd/bin/bash
export PATH=/var/run/etcd/bin:$PATH
# config file used to bootstrap the etcd cluster
config_file="$CONFIG_FILE_PATH"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
}

error_exit() {
  log "ERROR: $1"
  exit 1
}

# Standard library loading function - can be sourced by all scripts
load_common_library() {
  kblib_common_library_file="/scripts/kb-common.sh"
  etcd_common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  . "${kblib_common_library_file}"
  # shellcheck disable=SC1090
  . "${etcd_common_library_file}"
}

# Standard shellspec magic - can be used by all scripts
setup_shellspec() {
  ${__SOURCED__:+false} : || return 0
}

# execute etcdctl command with auto protocol detection
exec_etcdctl() {
  local endpoint="$1"
  shift

  if [[ "$endpoint" != http://* ]] && [[ "$endpoint" != https://* ]]; then
    if get_protocol "advertise-client-urls" | grep -q "https"; then
      endpoint="https://$endpoint"
    else
      endpoint="http://$endpoint"
    fi
  fi

  if get_protocol "advertise-client-urls" | grep -q "https"; then
    [ ! -d "$TLS_MOUNT_PATH" ] && echo "ERROR: TLS_MOUNT_PATH '$TLS_MOUNT_PATH' not found" >&2 && return 1
    for cert in ca.pem cert.pem key.pem; do
      [ ! -s "$TLS_MOUNT_PATH/$cert" ] && echo "ERROR: TLS certificate '$cert' missing or empty" >&2 && return 1
    done
    etcdctl --endpoints="$endpoint" --cacert="$TLS_MOUNT_PATH/ca.pem" --cert="$TLS_MOUNT_PATH/cert.pem" --key="$TLS_MOUNT_PATH/key.pem" "$@"
  else
    etcdctl --endpoints="$endpoint" "$@"
  fi
}

exec_bounded_etcdctl() {
  local endpoint="$1"
  shift
  exec_etcdctl "$endpoint" "$@" --dial-timeout=2s --command-timeout=6s
}

validate_local_leader() {
  local endpoint="${1:-127.0.0.1:2379}"
  local status

  if ! status=$(exec_bounded_etcdctl "$endpoint" endpoint status -w fields); then
    return 1
  fi

  printf '%s\n' "$status" | awk '
    /^"MemberID"[[:space:]]*:/ {
      if (++member_count != 1 || $0 !~ /^"MemberID"[[:space:]]*:[[:space:]]*[0-9]+[[:space:]]*$/) {
        malformed = 1
      }
      member_id = $0
      sub(/^[^:]*:[[:space:]]*/, "", member_id)
      sub(/[[:space:]]*$/, "", member_id)
      next
    }
    /^"Leader"[[:space:]]*:/ {
      if (++leader_count != 1 || $0 !~ /^"Leader"[[:space:]]*:[[:space:]]*[0-9]+[[:space:]]*$/) {
        malformed = 1
      }
      leader_id = $0
      sub(/^[^:]*:[[:space:]]*/, "", leader_id)
      sub(/[[:space:]]*$/, "", leader_id)
      next
    }
    END {
      if (malformed || member_count != 1 || leader_count != 1 ||
          member_id == "0" || leader_id == "0" ||
          ("id:" member_id) != ("id:" leader_id)) {
        exit 2
      }
    }
  '
}

get_protocol() {
  local url_type="$1"

  if grep "$url_type" "$config_file" | grep -q 'https'; then
    echo "https"
  else
    echo "http"
  fi
}

check_backup_file() {
  local backup_file="$1"

  if [ ! -f "$backup_file" ]; then
    error_exit "Backup file $backup_file does not exist"
  fi
  etcdutl snapshot status "$backup_file"
}

get_endpoint_adapt_lb() {
  local lb_endpoints="$1"
  local pod_name="$2"
  local fallback_endpoint="$3"
  local result_endpoint rc

  if [ -z "$lb_endpoints" ]; then
    canonicalize_endpoint_host "$fallback_endpoint"
    return
  fi

  if result_endpoint=$(printf '%s\n' "$lb_endpoints" | awk -v target="$pod_name" '
    function canonical_host(host, parts, count, i, result) {
      sub(/[.]$/, "", host)
      host = tolower(host)
      if (host == "" || length(host) > 253) {
        return ""
      }
      if (host ~ /^[0-9.]+$/) {
        count = split(host, parts, ".")
        if (count != 4) {
          return ""
        }
        result = ""
        for (i = 1; i <= 4; i++) {
          if (parts[i] !~ /^[0-9]+$/ || parts[i] + 0 > 255) {
            return ""
          }
          result = result (i == 1 ? "" : ".") (parts[i] + 0)
        }
        return result
      }
      count = split(host, parts, ".")
      for (i = 1; i <= count; i++) {
        if (length(parts[i]) < 1 || length(parts[i]) > 63 ||
            parts[i] !~ /^[a-z0-9][a-z0-9-]*$/ || parts[i] ~ /-$/) {
          return ""
        }
      }
      return host
    }
    {
      if (NR != 1) malformed = 1
      count = split($0, tokens, ",")
      for (i = 1; i <= count; i++) {
        token = tokens[i]
        if (token == "" || token ~ /^[^:]*:[^:]*:[^:]*$/) {
          malformed = 1
          continue
        }
        colon = index(token, ":")
        if (colon == 0) {
          key = token
          host = token
        } else {
          key = substr(token, 1, colon - 1)
          host = substr(token, colon + 1)
        }
        if (key !~ /^[a-z0-9][a-z0-9.-]*$/) {
          malformed = 1
          continue
        }
        host = canonical_host(host)
        if (host == "") {
          malformed = 1
          continue
        }
        keys[i] = key
        hosts[i] = host
        if (key == target) {
          target_count++
          target_host = host
        }
      }
    }
    END {
      if (malformed) {
        exit 2
      }
      if (target_count > 1) {
        exit 3
      }
      if (target_count == 0) {
        exit 10
      }
      for (i = 1; i <= count; i++) {
        if (keys[i] != target && hosts[i] == target_host) {
          exit 4
        }
      }
      print target_host
    }
  '); then
    log "Using exact LoadBalancer endpoint for $pod_name: $result_endpoint"
    printf '%s\n' "$result_endpoint"
    return 0
  else
    rc=$?
  fi

  if [ "$rc" -eq 10 ]; then
    result_endpoint=$(canonicalize_endpoint_host "$fallback_endpoint") || return 1
    log "mapping-missing-fallback-fqdn for $pod_name: $result_endpoint"
    printf '%s\n' "$result_endpoint"
    return 0
  fi

  return "$rc"
}

canonicalize_endpoint_host() {
  local host="$1"
  printf '%s\n' "$host" | awk '
    function fail() { exit 1 }
    {
      sub(/[.]$/, "")
      value = tolower($0)
      if (value == "" || length(value) > 253) fail()
      if (value ~ /^[0-9.]+$/) {
        count = split(value, parts, ".")
        if (count != 4) fail()
        result = ""
        for (i = 1; i <= 4; i++) {
          if (parts[i] !~ /^[0-9]+$/ || parts[i] + 0 > 255) fail()
          result = result (i == 1 ? "" : ".") (parts[i] + 0)
        }
        print result
        next
      }
      count = split(value, parts, ".")
      for (i = 1; i <= count; i++) {
        if (length(parts[i]) < 1 || length(parts[i]) > 63 ||
            parts[i] !~ /^[a-z0-9][a-z0-9-]*$/ || parts[i] ~ /-$/) fail()
      }
      print value
    }
  '
}

build_current_contact_candidates() {
  local exclude_name="$1"
  local expected_client_protocol="$2"
  local exclude_id="${3:-}"
  local output_mode="${4:-contacts}"
  local expected_peer_protocol="${5:-$expected_client_protocol}"

  awk -v exclude_name="$exclude_name" \
    -v expected_client_protocol="$expected_client_protocol" \
    -v expected_peer_protocol="$expected_peer_protocol" \
    -v exclude_id="$exclude_id" -v output_mode="$output_mode" '
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
    function canonical_url(value, expected_port, required_protocol, marker, rest, host, port, protocol) {
      marker = index(value, "://")
      if (marker == 0) return ""
      protocol = substr(value, 1, marker - 1)
      rest = substr(value, marker + 3)
      if (protocol != required_protocol || rest !~ /:[0-9]+$/) return ""
      port = rest
      sub(/^.*:/, "", port)
      host = rest
      sub(/:[0-9]+$/, "", host)
      host = canonical_host(host)
      if (host == "" || ("port:" port) != ("port:" expected_port)) return ""
      return protocol "://" host ":" port
    }
    function clear_block(key) {
      in_member = 0
      member_id = ""
      member_name = ""
      id_seen = 0
      name_seen = 0
      peer_count = 0
      client_count = 0
      client_empty_count = 0
      for (key in block_clients) delete block_clients[key]
    }
    function finish_member(i, url) {
      if (!in_member) return
      if (id_seen != 1 || name_seen != 1 || peer_count < 1) malformed = 1
      if (member_name == "") {
        if (client_count > 0) malformed = 1
      } else if (client_count < 1 || client_empty_count > 0) {
        malformed = 1
      }
      if (member_name != "" && member_name != exclude_name &&
          ("id:" member_id) != ("id:" exclude_id)) {
        for (i = 1; i <= client_count; i++) {
          url = block_clients[i]
          if (!candidate_seen[url]++) candidates[++candidate_count] = url
        }
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
      if (!in_member || name_seen || $0 !~ /^"Name"[[:space:]]*:[[:space:]]*"[^"]*"[[:space:]]*$/) {
        malformed = 1
      } else {
        member_name = field_value($0)
        if (member_name != "" && member_names[member_name]++) malformed = 1
        name_seen = 1
      }
      next
    }
    /^"PeerURL"[[:space:]]*:/ {
      if (!in_member || $0 !~ /^"PeerURL"[[:space:]]*:[[:space:]]*"[^"]+"[[:space:]]*$/ ||
          canonical_url(field_value($0), 2380, expected_peer_protocol) == "") {
        malformed = 1
      } else {
        peer_count++
      }
      next
    }
    /^"ClientURL"[[:space:]]*:/ {
      if (!in_member || $0 !~ /^"ClientURL"[[:space:]]*:[[:space:]]*"[^"]*"[[:space:]]*$/) {
        malformed = 1
      } else {
        value = field_value($0)
        if (value == "") {
          client_empty_count++
        } else {
          value = canonical_url(value, 2379, expected_client_protocol)
          if (value == "") malformed = 1
          else block_clients[++client_count] = value
        }
      }
      next
    }
    END {
      finish_member()
      if (!saw_member || malformed) exit 2
      if (output_mode == "validate-only") exit 0
      if (candidate_count > 8) exit 3
      if (candidate_count == 0) exit 4
      for (i = 1; i <= candidate_count; i++) {
        printf "%s%s", (i == 1 ? "" : ","), candidates[i]
      }
      print ""
    }
  '
}

parse_endpoint_field() {
  local endpoint="$1"
  local field_name="$2"
  local status field_value

  if ! status=$(exec_etcdctl "$endpoint" endpoint status -w fields); then
    error_exit "Failed to get endpoint status from $endpoint"
  fi

  field_value=$(echo "$status" | awk -F': ' -v field="\"$field_name\"" '$1 ~ field {gsub(/[^0-9]/, "", $2); print $2}')

  [ -z "$field_value" ] && error_exit "Failed to extract $field_name from endpoint status"

  echo "$field_value"
}

is_leader() {
  local contact_point="$1"
  local member_id leader_id

  member_id=$(parse_endpoint_field "$contact_point" "MemberID")
  leader_id=$(parse_endpoint_field "$contact_point" "Leader")

  [ "$member_id" = "$leader_id" ]
}

get_member_and_leader_id() {
  local endpoint="$1"

  member_id=$(parse_endpoint_field "$endpoint" "MemberID")
  leader_id=$(parse_endpoint_field "$endpoint" "Leader")

  echo "$member_id $leader_id"
}

get_member_id() {
  local endpoint="$1"
  parse_endpoint_field "$endpoint" "MemberID"
}

get_member_id_hex() {
  local endpoint="$1"
  member_id=$(parse_endpoint_field "$endpoint" "MemberID")
  printf "%x" "$member_id"
}
