#!/bin/bash

# Decode the flat member objects returned by etcd's peer /members endpoint.
# No jq/Python is available in the engine images. Accept the documented schema,
# parse JSON strings/arrays explicitly, and emit nothing for invalid input.
peer_members_to_list() {
  awk '
    function fail() { bad=1; exit 1 }
    function next_token(    c, e) {
      while (substr(input, pos, 1) ~ /[ \t\r\n]/ && pos <= length(input)) pos++
      c=substr(input, pos++, 1); token=c; value=""
      if (c == "\"") {
        while (pos <= length(input)) {
          c=substr(input, pos++, 1)
          if (c == "\"") return
          if (c == "\\") {
            e=substr(input, pos++, 1)
            if (e != "/" && e != "\\" && e != "\"") fail()
            c=e
          }
          if (c ~ /[[:cntrl:]]/) fail()
          value=value c
        }
        fail()
      }
      if (c ~ /[0-9]/) {
        token="number"; value=c
        while (substr(input, pos, 1) ~ /[0-9]/ && pos <= length(input)) value=value substr(input, pos++, 1)
      }
      if (c ~ /[a-z]/) {
        token=c
        while (substr(input, pos, 1) ~ /[a-z]/ && pos <= length(input)) token=token substr(input, pos++, 1)
      }
    }
    function expect(t) { if (token != t) fail(); next_token() }
    function string_value(    v) { if (token != "\"") fail(); v=value; next_token(); return v }
    function urls(    result, u) {
      expect("["); count=0; result=""
      while (token != "]") {
        u=string_value()
        if (u !~ /^https?:\/\/[^, =|&\\]+:[0-9]+$/) fail()
        result=result (count++ ? ";" : "") u
        if (token != ",") break
        next_token()
      }
      expect("]"); return result
    }
    function member(    key, id, name, peer, clients, learner, seen) {
      id=""; name=""; peer=""; clients=""; learner="false"; seen="|"
      expect("{")
      while (token != "}") {
        key=string_value(); expect(":")
        if (index(seen, "|" key "|")) fail()
        seen=seen key "|"
        if (key == "id") {
          if (token == "number") { id=value; next_token() }
          else id=string_value()
        }
        else if (key == "name") name=string_value()
        else if (key == "peerURLs") { peer=urls(); if (count != 1) fail() }
        else if (key == "clientURLs") clients=urls()
        else if (key == "isLearner") {
          if (token != "true" && token != "false") fail()
          learner=token; next_token()
        } else fail()
        if (token != ",") break
        next_token()
      }
      expect("}")
      if (id !~ /^[0-9a-f]+$/ || peer == "" || name !~ /^[a-zA-Z0-9_.-]*$/) fail()
      output=output id ", " (name == "" ? "unstarted" : "started") ", " name ", " peer ", " clients ", " learner "\n"
      total++
    }
    { input=input $0 "\n" }
    END {
      if (bad) exit 1
      pos=1; next_token(); expect("[")
      while (token != "]") {
        member()
        if (token != ",") break
        next_token()
      }
      expect("]")
      if (token != "" || !total) exit 1
      printf "%s", output
    }'
}

# Peer /members reads locally applied membership, exactly as etcd bootstrap
# does. It does not need quorum (unlike etcdctl member list in etcd 3.5).
read_peer_members() {
  local endpoints="$1" timeout="$2" endpoint body remaining
  local deadline=$((SECONDS + timeout))
  local peers tls_args=()
  IFS=',' read -ra peers <<< "$endpoints"
  for endpoint in "${peers[@]}"; do
    remaining=$((deadline - SECONDS))
    [ "$remaining" -gt 0 ] || return 1
    tls_args=()
    if [[ "$endpoint" == https://* ]]; then
      local cert
      for cert in ca.pem cert.pem key.pem; do
        [ -s "$TLS_MOUNT_PATH/$cert" ] || return 1
      done
      tls_args=(--cacert "$TLS_MOUNT_PATH/ca.pem" --cert "$TLS_MOUNT_PATH/cert.pem" --key "$TLS_MOUNT_PATH/key.pem")
    fi
    if body=$(curl --fail --silent --show-error --connect-timeout 3 --max-time "$remaining" "${tls_args[@]}" "$endpoint/members") &&
      printf '%s\n' "$body" | peer_members_to_list; then
      return 0
    fi
  done
  return 1
}
