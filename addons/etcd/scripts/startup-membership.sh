#!/bin/bash

# A failed first bootstrap can leave an empty member directory. Only persisted
# WAL segments distinguish a restart (including restored state) from a new join.
etcd_has_wal() {
  [ -d "$DATA_DIR/member/wal" ] &&
    [ -n "$(find "$DATA_DIR/member/wal" -type f -name '*.wal' -print -quit)" ]
}

# Emit the engine's complete initial-cluster mapping only after this exact peer
# is registered. Another unnamed member cannot safely be named from Pod order.
registered_initial_cluster() {
  local members="$1" own_peer="$2"
  printf '%s\n' "$members" | awk -F ', ' -v name="$CURRENT_POD_NAME" -v peer="$own_peer" '
    NF != 6 || $1 !~ /^[0-9a-f]+$/ || ($2 != "started" && $2 != "unstarted") { invalid=1; next }
    {
      n=$3
      if ($4 == peer) {
        found++
        if ((n != "" && n != name) || $6 != "false") invalid=1
        n=name
      } else if (n == name) invalid=1
      if (n == "" || n !~ /^[a-zA-Z0-9_.-]+$/ || $4 !~ /^https?:\/\/[^, =|]+:[0-9]+$/) invalid=1
      if (names[n]++ || urls[$4]++) invalid=1
      config=config sep n "=" $4; sep=","
    }
    END {
      if (invalid || found != 1) exit 1
      print config
    }'
}

wait_for_member_registration() {
  local state endpoints="" fqdn pod endpoint own_peer members initial_cluster
  local deadline remaining request_timeout
  state=$(parse_config_value initial-cluster-state "$default_conf")
  [ "$state" = existing ] || return 0
  if etcd_has_wal; then
    log "Existing WAL detected; skipping startup registration wait"
    return 0
  fi

  own_peer=$(parse_config_value initial-advertise-peer-urls "$default_conf")
  local peers
  IFS=',' read -ra peers <<< "$PEER_FQDNS"
  for fqdn in "${peers[@]}"; do
    pod="${fqdn%%.*}"
    [ "$pod" = "$CURRENT_POD_NAME" ] && continue
    endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$pod" "$fqdn")
    endpoints="${endpoints:+$endpoints,}$(get_protocol advertise-client-urls)://$endpoint:2379"
  done
  if [ -z "$endpoints" ]; then
    error_exit "No existing peer available for startup registration check"
    return 1
  fi

  log "Waiting for startup registration: target=$CURRENT_POD_NAME peer=$own_peer timeout=120s"
  deadline=$((SECONDS + 120))
  while [ "$SECONDS" -lt "$deadline" ]; do
    remaining=$((deadline - SECONDS))
    request_timeout=5
    [ "$remaining" -lt 5 ] && request_timeout="$remaining"
    if members=$(exec_etcdctl "$endpoints" --dial-timeout=3s --command-timeout="${request_timeout}s" member list -w simple) &&
      initial_cluster=$(registered_initial_cluster "$members" "$own_peer"); then
      sed -i.bak "s|^initial-cluster:.*|initial-cluster: $initial_cluster|" "$default_conf"
      rm -f "$default_conf.bak"
      log "Startup registration confirmed; initial-cluster=$initial_cluster"
      return 0
    fi
    log "Startup registration not ready; waiting for a consistent member list"
    [ "$SECONDS" -ge "$deadline" ] || sleep 1
  done
  error_exit "Timed out waiting for startup registration of $CURRENT_POD_NAME ($own_peer)"
  return 1
}
