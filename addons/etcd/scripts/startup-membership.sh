#!/bin/bash

# A failed first bootstrap can leave an empty member directory. Only persisted
# WAL segments distinguish a restart (including restored state) from a new join.
etcd_has_wal() {
  [ -d "$DATA_DIR/member/wal" ] &&
    [ -n "$(find "$DATA_DIR/member/wal" -type f -name '*.wal' -print -quit)" ]
}

# Emit the engine's complete initial-cluster mapping only after this exact peer
# is registered. Resolve unnamed peers only through the exact URL mapping
# already generated from Pod FQDNs / configured LoadBalancer endpoints.
registered_initial_cluster() {
  local members="$1" own_peer="$2" expected_cluster="${3:-}"
  printf '%s\n' "$members" | awk -F ', ' -v name="$CURRENT_POD_NAME" -v peer="$own_peer" -v expected="$expected_cluster" '
    BEGIN {
      count=split(expected, entries, ",")
      for (i=1; i<=count; i++) {
        if (entries[i] == "") continue
        if (split(entries[i], pair, "=") != 2 || pair[1] == "" || pair[2] == "" || mapping[pair[2]] != "" || expected_names[pair[1]]++) invalid=1
        mapping[pair[2]]=pair[1]
      }
    }
    NF != 6 || $1 !~ /^[0-9a-f]+$/ || ($2 != "started" && $2 != "unstarted") { invalid=1; next }
    {
      n=$3
      if (n == "") n=mapping[$4]
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

# etcd's getRemotePeerURLs sorts the URLs from initial-cluster, independently
# of Pod order and of the order in which the cluster mapping was generated.
initial_cluster_peer_endpoints() {
  printf '%s\n' "$1" | tr ',' '\n' |
    awk -F '=' -v name="$CURRENT_POD_NAME" '$1 != name { print $2 }' |
    LC_ALL=C sort -u | paste -sd, -
}

wait_for_member_registration() {
  local state endpoints own_peer members initial_cluster bootstrap_endpoints
  local deadline remaining expected_cluster
  local last_members="<not observed>" query_error=""
  state=$(parse_config_value initial-cluster-state "$default_conf")
  [ "$state" = existing ] || return 0
  if etcd_has_wal; then
    log "Existing WAL detected; skipping startup registration wait"
    return 0
  fi

  own_peer=$(parse_config_value initial-advertise-peer-urls "$default_conf")
  expected_cluster=$(parse_config_value initial-cluster "$default_conf")
  endpoints=$(initial_cluster_peer_endpoints "$expected_cluster")
  if [ -z "$endpoints" ]; then
    log "Last observed membership: <query not attempted: no remote peer>"
    error_exit "No existing peer available for startup registration check"
    return 1
  fi

  log "Waiting for startup registration: target=$CURRENT_POD_NAME peer=$own_peer timeout=120s"
  deadline=$((SECONDS + 120))
  while [ "$SECONDS" -lt "$deadline" ]; do
    remaining=$((deadline - SECONDS))
    if members=$(read_peer_members "$endpoints" "$remaining"); then
      last_members="${members:-<(empty)>}"
      query_error=""
      if initial_cluster=$(registered_initial_cluster "$members" "$own_peer" "$expected_cluster"); then
        bootstrap_endpoints=$(initial_cluster_peer_endpoints "$initial_cluster")
        if [ -n "$bootstrap_endpoints" ] && [ "$bootstrap_endpoints" = "$endpoints" ]; then
          sed -i.bak "s|^initial-cluster:.*|initial-cluster: $initial_cluster|" "$default_conf"
          rm -f "$default_conf.bak"
          log "Startup registration confirmed; initial-cluster=$initial_cluster"
          return 0
        fi
        # Membership may contain peers absent from the original Pod mapping.
        # Recheck using the exact URLs etcd will query from the new config.
        endpoints="$bootstrap_endpoints"
      fi
    else
      query_error=" (query failed)"
    fi
    log "Startup registration not ready; waiting for a consistent member list"
    # A responsive stale peer is also the one etcd will select on bootstrap.
    # Keep waiting for it; rotating to a fresher peer only hides the race.
    [ "$SECONDS" -ge "$deadline" ] || sleep 1
  done
  log "Last observed membership$query_error: $(printf '%s\n' "$last_members" | awk 'NR <= 20 { print substr($0, 1, 512) }')"
  error_exit "Timed out waiting for startup registration of $CURRENT_POD_NAME ($own_peer)"
  return 1
}
