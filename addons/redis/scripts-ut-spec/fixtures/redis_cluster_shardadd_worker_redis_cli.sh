#!/usr/bin/env bash

set -u

scenario=${FAKE_SCENARIO:-stable}
state_file=${FAKE_STATE_FILE:?missing FAKE_STATE_FILE}
log_file=${FAKE_REDIS_CLI_LOG:?missing FAKE_REDIS_CLI_LOG}
major=${FAKE_REDIS_MAJOR:-7}

printf '%q ' "$@" >>"$log_file"
printf '\n' >>"$log_file"

if [ "${1:-}" = "--version" ]; then
  if [ "$scenario" = "hang_version" ]; then
    trap 'printf "version-terminated\n" >>"$log_file"; exit 143' TERM INT
    sleep 30
  fi
  printf 'redis-cli %s.0.0\n' "$major"
  exit 0
fi

host=host1
previous=""
for argument in "$@"; do
  if [ "$previous" = "-h" ]; then
    host=$argument
  fi
  previous=$argument
done

command_line=" $* "
new_master=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
old_master=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
old_replica=cccccccccccccccccccccccccccccccccccccccc
new_replica=dddddddddddddddddddddddddddddddddddddddd

emit_nodes() {
  old_flags=master
  new_flags=master
  new_master_parent=-
  if [ "$scenario" = "replica_new" ]; then
    new_flags=slave
    new_master_parent=$old_master
  fi
  if [ "$host" = "host1" ]; then
    old_flags=myself,master
  elif [ "$host" = "host2" ]; then
    new_flags=myself,$new_flags
  fi

  old_replica_flags=slave
  new_replica_flags=slave
  if [ "$host" = "host3" ]; then
    old_replica_flags=myself,slave
  elif [ "$host" = "host4" ]; then
    new_replica_flags=myself,slave
  fi

  if [ "$scenario" = "inconsistent" ] && [ "$host" = "host2" ]; then
    printf '%s 10.0.0.1:6379@16379,host1 %s - 0 0 1 connected 0-8190\n' "$old_master" "$old_flags"
    printf '%s 10.0.0.2:6379@16379,host2 %s - 0 0 2 connected 8191-16383\n' "$new_master" "$new_flags"
    printf '%s 10.0.0.3:6379@16379,host3 %s %s 0 0 3 connected\n' "$old_replica" "$old_replica_flags" "$old_master"
    printf '%s 10.0.0.4:6379@16379,host4 %s %s 0 0 4 connected\n' "$new_replica" "$new_replica_flags" "$new_master"
    return
  fi

  if { [ "$scenario" = "empty" ] && [ ! -s "$state_file" ]; } ||
     { [ "$scenario" = "partial_open" ] && ! grep -q '^rebalanced$' "$state_file" 2>/dev/null; } ||
     { [ "$scenario" = "interrupted" ] && ! grep -q '^rebalanced$' "$state_file" 2>/dev/null; }; then
    printf '%s 10.0.0.1:6379@16379,host1 %s - 0 0 1 connected 0-16383\n' "$old_master" "$old_flags"
    if [ "$scenario" != "missing_new" ]; then
      printf '%s 10.0.0.2:6379@16379,host2 %s %s 0 0 2 connected\n' "$new_master" "$new_flags" "$new_master_parent"
    fi
    printf '%s 10.0.0.3:6379@16379,host3 %s %s 0 0 3 connected\n' "$old_replica" "$old_replica_flags" "$old_master"
    if [ "$scenario" != "missing_new" ]; then
      printf '%s 10.0.0.4:6379@16379,host4 %s %s 0 0 4 connected\n' "$new_replica" "$new_replica_flags" "$new_master"
    fi
    return
  fi

  printf '%s 10.0.0.1:6379@16379,host1 %s - 0 0 1 connected 0-8191\n' "$old_master" "$old_flags"
  if [ "$scenario" != "missing_new" ]; then
    printf '%s 10.0.0.2:6379@16379,host2 %s %s 0 0 2 connected 8192-16383\n' "$new_master" "$new_flags" "$new_master_parent"
  fi
  printf '%s 10.0.0.3:6379@16379,host3 %s %s 0 0 3 connected\n' "$old_replica" "$old_replica_flags" "$old_master"
  if [ "$scenario" != "missing_new" ]; then
    printf '%s 10.0.0.4:6379@16379,host4 %s %s 0 0 4 connected\n' "$new_replica" "$new_replica_flags" "$new_master"
  fi
}

if [[ "$command_line" == *" cluster nodes "* ]]; then
  if [ "$scenario" = "hang" ]; then
    trap 'printf "terminated\n" >>"$log_file"; exit 143' TERM INT
    sleep 30
  fi
  emit_nodes
  exit 0
fi

if [[ "$command_line" == *" cluster info "* ]]; then
  cluster_size=2
  if { [ "$scenario" = "empty" ] && [ ! -s "$state_file" ]; } ||
     { [ "$scenario" = "partial_open" ] && ! grep -q '^rebalanced$' "$state_file" 2>/dev/null; } ||
     { [ "$scenario" = "interrupted" ] && ! grep -q '^rebalanced$' "$state_file" 2>/dev/null; }; then
    cluster_size=1
  fi
  printf 'cluster_state:ok\n'
  printf 'cluster_slots_assigned:16384\n'
  printf 'cluster_slots_ok:16384\n'
  printf 'cluster_slots_pfail:0\n'
  printf 'cluster_slots_fail:0\n'
  printf 'cluster_size:%s\n' "$cluster_size"
  exit 0
fi

if [[ "$command_line" == *" --cluster check "* ]]; then
  if [ "$scenario" = "partial_open" ] && [ ! -s "$state_file" ]; then
    printf '[WARNING] The following slots are open: 8192\n'
    printf '[WARNING] Node has slots in importing state\n'
    exit 0
  fi
  if [ "$scenario" = "interrupted" ] && grep -q '^interrupted$' "$state_file" 2>/dev/null; then
    printf '[WARNING] The following slots are open: 8192\n'
    printf '[WARNING] Node has slots in migrating state\n'
    exit 0
  fi
  if [ "$scenario" = "unknown" ]; then
    printf '[ERR] cluster metadata could not be classified\n'
    exit 0
  fi
  printf '[OK] All 16384 slots covered.\n'
  exit 0
fi

if [[ "$command_line" == *" --cluster fix "* ]]; then
  printf 'fixed\n' >"$state_file"
  printf 'fix complete\n'
  exit 0
fi

if [[ "$command_line" == *" --cluster rebalance "* ]]; then
  if [ "$scenario" = "interrupted" ] && [ ! -s "$state_file" ]; then
    printf 'interrupted\n' >"$state_file"
    printf 'rebalance interrupted\n' >&2
    exit 70
  fi
  printf 'rebalanced\n' >"$state_file"
  printf 'rebalance complete\n'
  exit 0
fi

printf 'unexpected redis-cli invocation: %s\n' "$*" >&2
exit 64
