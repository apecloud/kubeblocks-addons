#!/bin/bash

set_tcp_keepalive_params() {
  local keepalive_time=${1:-1}
  local keepalive_intvl=${2:-11}
  local keepalive_probes=${3:-3}

  echo "Setting TCP keepalive parameters:"
  echo "  - net.ipv4.tcp_keepalive_time=$keepalive_time"
  echo "  - net.ipv4.tcp_keepalive_intvl=$keepalive_intvl"
  echo "  - net.ipv4.tcp_keepalive_probes=$keepalive_probes"

  sysctl -w net.ipv4.tcp_keepalive_time=$keepalive_time
  sysctl -w net.ipv4.tcp_keepalive_intvl=$keepalive_intvl
  sysctl -w net.ipv4.tcp_keepalive_probes=$keepalive_probes
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
set_tcp_keepalive_params 1 11 3