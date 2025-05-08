function get_mode() {
  local mode=$(echo srvr | nc 127.0.0.1 9181 | grep Mode)
  echo "$mode" | awk '{print $2}'
}

function get_keeper_role() {
  local mode=$(get_mode)
  if [ "$mode" == "standalone" ]; then
    printf "leader"
  elif [ "$mode" == "follower" ] || [ "$mode" == "leader" ] || [ "$mode" == "observer" ] ; then
    printf "%s" "$mode"
  fi
}

get_keeper_role