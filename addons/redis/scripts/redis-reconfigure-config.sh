#!/bin/sh

# Controller passes one [key, value] pair per invocation via argv.
# $1 = parameter name, $2 = parameter value.

init_reconfigure_env() {
  service_port=${SERVICE_PORT:-6379}
  auth_arg=""
  [ -z "${REDIS_DEFAULT_PASSWORD:-}" ] || auth_arg="-a ${REDIS_DEFAULT_PASSWORD}"
}

to_bytes() {
  case "$1" in
    *[kK][bB]) echo $(( ${1%[kK][bB]} * 1024 )) ;;
    *[mM][bB]) echo $(( ${1%[mM][bB]} * 1024 * 1024 )) ;;
    *[gG][bB]) echo $(( ${1%[gG][bB]} * 1024 * 1024 * 1024 )) ;;
    *) echo "$1" ;;
  esac
}

normalize_tokens() {
  set -- $1
  _nt_out=""
  for _nt_tok; do
    _nt_out="${_nt_out:+$_nt_out }$(to_bytes "$_nt_tok")"
  done
  echo "$_nt_out"
}

values_match() {
  [ "$1" = "$2" ] && return 0
  [ "$(to_bytes "$1")" = "$(to_bytes "$2")" ] && return 0
  return 1
}

apply_parameter() {
  _ap_key="$1"
  _ap_value="$2"
  _ap_subkey=""
  [ "$_ap_value" = '""' ] && _ap_value=""

  # Handle subkey parameters: "client-output-buffer-limit normal" -> key + subkey
  case "$_ap_key" in
    *" "*)
      _ap_subkey="${_ap_key#* }"
      _ap_key="${_ap_key%% *}"
      _ap_value="${_ap_subkey} ${_ap_value}"
      ;;
  esac

  # shellcheck disable=SC2086
  redis-cli ${REDIS_CLI_TLS_CMD:-} -p "$service_port" $auth_arg CONFIG SET "$_ap_key" "$_ap_value" || {
    echo "ERROR: CONFIG SET $_ap_key failed (redis-cli exit $?)" >&2
    return 1
  }

  _ap_actual=$(redis-cli ${REDIS_CLI_TLS_CMD:-} -p "$service_port" $auth_arg CONFIG GET "$_ap_key" 2>/dev/null | awk 'NR==2 {print}')
  if [ -n "$_ap_subkey" ]; then
    _ap_norm_expected="$(normalize_tokens "$_ap_value")"
    _ap_norm_actual="$(normalize_tokens "$_ap_actual")"
    case "$_ap_norm_actual" in
      *"$_ap_norm_expected"*) ;;
      *) echo "ERROR: CONFIG SET $_ap_key readback does not contain '$_ap_value'" >&2; return 1 ;;
    esac
  else
    if [ -z "$_ap_actual" ] && [ -n "$_ap_value" ]; then
      echo "ERROR: CONFIG GET $_ap_key returned nothing after SET" >&2
      return 1
    fi
    if ! values_match "$_ap_actual" "$_ap_value"; then
      echo "ERROR: CONFIG SET $_ap_key readback mismatch: engine='$_ap_actual', expected='$_ap_value'" >&2
      return 1
    fi
  fi

  echo "INFO: CONFIG SET $_ap_key='$_ap_value' applied and verified" >&2
  return 0
}

${__SOURCED__:+false} : || return 0

if [ $# -lt 2 ]; then
  echo "ERROR: reconfigure requires key and value arguments (received $# args)" >&2
  exit 1
fi

init_reconfigure_env
apply_parameter "$1" "$2"
exit $?
