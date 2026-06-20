#!/bin/sh

init_reconfigure_env() {
  dynamic_allowlist="${DYNAMIC_ALLOWLIST:-}"
  service_port=${SERVICE_PORT:-6379}
  auth_arg=""
  [ -z "${REDIS_DEFAULT_PASSWORD:-}" ] || auth_arg="-a ${REDIS_DEFAULT_PASSWORD}"
}

is_dynamic() {
  case ",$dynamic_allowlist," in *,"$1",*) return 0 ;; esac
  return 1
}

to_bytes() {
  case "$1" in
    *[kK][bB]) echo $(( ${1%[kK][bB]} * 1024 )) ;;
    *[mM][bB]) echo $(( ${1%[mM][bB]} * 1024 * 1024 )) ;;
    *[gG][bB]) echo $(( ${1%[gG][bB]} * 1024 * 1024 * 1024 )) ;;
    *) echo "$1" ;;
  esac
}

values_match() {
  [ "$1" = "$2" ] && return 0
  [ "$(to_bytes "$1")" = "$(to_bytes "$2")" ] && return 0
  return 1
}

reconfigure_parameter() {
  param_name="${1:?missing parameter name}"
  param_value="${2:-}"

  if ! is_dynamic "$param_name"; then
    echo "INFO: $param_name not in DYNAMIC_ALLOWLIST, skipping" >&2
    return 0
  fi

  _set_out=$(redis-cli ${REDIS_CLI_TLS_CMD:-} -p "$service_port" $auth_arg CONFIG SET "$param_name" "$param_value" 2>&1)
  case "$_set_out" in
    OK) ;;
    *) echo "ERROR: CONFIG SET $param_name: $_set_out" >&2; return 1 ;;
  esac

  _rv=$(redis-cli ${REDIS_CLI_TLS_CMD:-} -p "$service_port" $auth_arg CONFIG GET "$param_name" 2>/dev/null | awk '
    NR==1 { found=1 }
    NR==2 { val=$0 }
    END { if (found) printf "1|%s", val; else printf "0|" }
  ')
  _rv_found="${_rv%%|*}"
  _rv_actual="${_rv#*|}"

  if [ "$_rv_found" != "1" ]; then
    echo "ERROR: CONFIG GET $param_name returned nothing after SET" >&2
    return 1
  fi
  if ! values_match "$_rv_actual" "$param_value"; then
    echo "ERROR: CONFIG SET $param_name readback mismatch: engine='$_rv_actual', expected='$param_value'" >&2
    return 1
  fi

  echo "INFO: CONFIG SET $param_name applied" >&2
  return 0
}

${__SOURCED__:+false} : || return 0

init_reconfigure_env
reconfigure_parameter "$@"
exit $?
