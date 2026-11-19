#!/bin/bash
set -e

# pid stores the process id of the proxysql child; 0 until proxysql is spawned
# so a signal arriving before the spawn is a safe no-op.
declare -i pid=0

# term_handler forwards pod-termination signals to the proxysql child so it
# shuts down cleanly instead of being SIGKILLed after the termination grace
# period, then terminates the wrapper itself. It reaps the child exactly once
# and exits, so the main path never runs a second `wait` (which would fail with
# "not a child" / 127 under `set -e`). Defined before the shellspec guard so it
# stays unit-testable.
term_handler() {
  if [ "${pid}" -ne 0 ]; then
    kill -TERM "${pid}" 2>/dev/null || true
    wait "${pid}" 2>/dev/null || true
  fi
  exit 0
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# use the current scrip name while putting log
script_name=${0##*/}

if [ "${FRONTEND_TLS_ENABLED}" == "true" ]; then
    cp /var/lib/frontend/server/ca.crt /var/lib/proxysql/proxysql-ca.pem
    cp /var/lib/frontend/server/tls.crt /var/lib/proxysql/proxysql-cert.pem
    cp /var/lib/frontend/server/tls.key /var/lib/proxysql/proxysql-key.pem
fi

# If command has arguments, prepend proxysql
if [ "${1:0:1}" = '-' ]; then
    CMDARG="$@"
fi

# if test by shellspec include, just return 0
if [ "${__SOURCED__:+x}" ]; then
  return 0
fi

# Install the signal trap as the first thing in the main path (pid is still 0)
# so any SIGTERM during startup — config rendering, spawn, or the configure
# helper — is handled instead of killing the wrapper with the default action.
trap 'term_handler' SIGTERM SIGINT

# These paths are overridable so the signal-handling contract can be exercised
# end-to-end in tests. They default to the in-image paths (no behavior change).
: "${PROXYSQL_CONFIGURE_SCRIPT:=/scripts/proxysql/configure-proxysql.sh}"
: "${PROXYSQL_CONFIG_TPL:=/config/custom-config/proxysql.tpl}"
: "${PROXYSQL_CONFIG_OUT:=/proxysql.cnf}"

function replace_config_variables() {
  cat "${PROXYSQL_CONFIG_TPL}" > "${PROXYSQL_CONFIG_OUT}"
  sed -i "s|\${PROXYSQL_MONITOR_PASSWORD}|${PROXYSQL_MONITOR_PASSWORD}|g" "${PROXYSQL_CONFIG_OUT}"
  sed -i "s|\${PROXYSQL_CLUSTER_PASSWORD}|${PROXYSQL_CLUSTER_PASSWORD}|g" "${PROXYSQL_CONFIG_OUT}"
  sed -i "s|\${PROXYSQL_ADMIN_PASSWORD}|${PROXYSQL_ADMIN_PASSWORD}|g" "${PROXYSQL_CONFIG_OUT}"
}

echo "Configuring proxysql ..."
replace_config_variables

# Run proxysql as a child (not exec) so this wrapper stays alive as the
# container init process and can forward signals to it via the trap above.
proxysql -c /proxysql.cnf -f $CMDARG &
pid=$!

"${PROXYSQL_CONFIGURE_SCRIPT}"

echo "Waiting for proxysql ..."
wait "${pid}"
