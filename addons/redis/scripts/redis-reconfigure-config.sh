#!/bin/sh

init_reconfigure_env() {
  config_file="/etc/conf/redis.conf"
  dynamic_allowlist="${DYNAMIC_ALLOWLIST:-}"
  freshness_check="${REDIS_RECONFIGURE_FRESHNESS_CHECK:-true}"
  projection_fresh_age_seconds="${REDIS_RECONFIGURE_PROJECTION_FRESH_AGE_SECONDS:-10}"
  projection_wait_seconds="${REDIS_RECONFIGURE_PROJECTION_WAIT_SECONDS:-15}"
  service_port=${SERVICE_PORT:-6379}
  auth_arg=""
  [ -z "${REDIS_DEFAULT_PASSWORD:-}" ] || auth_arg="-a ${REDIS_DEFAULT_PASSWORD}"
}

is_dynamic() {
  case ",$dynamic_allowlist," in *,"$1",*) return 0 ;; esac
  return 1
}

engine_has_key() {
  printf '%s\n' "$engine_dump" | grep -qxF "$1"
}

engine_value() {
  printf '%s\n' "$engine_dump" | awk -v k="$1" 'found {print; found=0; next} $0==k {found=1}'
}

normalize_value() {
  case "$1" in
    \"*\") _nv="${1#\"}"; echo "${_nv%\"}" ;;
    *) echo "$1" ;;
  esac
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

verify_engine_state() {
  _vf_check=$(redis-cli ${REDIS_CLI_TLS_CMD:-} -p "$service_port" $auth_arg CONFIG GET "$1" 2>/dev/null | awk '
    NR==1 { found=1 }
    NR==2 { val=$0 }
    END { if (found) printf "1|%s", val; else printf "0|" }
  ')
  _vf_found="${_vf_check%%|*}"
  _vf_actual="${_vf_check#*|}"
  if [ "$_vf_found" != "1" ]; then
    echo "ERROR: CONFIG GET $1 returned nothing after SET" >&2
    return 1
  fi
  if ! values_match "$_vf_actual" "$2"; then
    echo "ERROR: CONFIG SET $1 readback mismatch: engine reports '$_vf_actual', expected '$2'" >&2
    return 1
  fi
  if [ "$_vf_actual" != "$2" ]; then
    echo "INFO: CONFIG SET $1 applied; engine reports '$_vf_actual' (rendered '$2')" >&2
  fi
  return 0
}

reload_parameter() {
  /scripts/reload-parameter.sh "$@"
}

now_seconds() {
  date +%s
}

file_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

readlink_target() {
  readlink "$1" 2>/dev/null
}

config_fingerprint() {
  cksum "$1" 2>/dev/null | awk '{print $1 ":" $2}'
}

ensure_projected_config_fresh() {
  freshness_check="${freshness_check:-true}"
  projection_fresh_age_seconds="${projection_fresh_age_seconds:-10}"
  projection_wait_seconds="${projection_wait_seconds:-15}"

  [ "$freshness_check" = "false" ] && return 0

  _epcf_current=$(config_fingerprint "$config_file") || {
    echo "ERROR: cannot fingerprint rendered config: $config_file" >&2
    return 1
  }

  _epcf_config_dir=$(dirname "$config_file")
  _epcf_data_link="${_epcf_config_dir}/..data"
  if [ ! -L "$_epcf_data_link" ]; then
    echo "ERROR: projected config freshness check failed: $_epcf_data_link is not a symlink, mounted='$_epcf_current', retry-safe: yes" >&2
    return 1
  fi

  _epcf_initial_link=$(readlink_target "$_epcf_data_link")
  _epcf_mtime=$(file_mtime "$_epcf_data_link") || _epcf_mtime=""
  _epcf_now=$(now_seconds)
  if [ -n "$_epcf_mtime" ]; then
    _epcf_age=$((_epcf_now - _epcf_mtime))
    if [ "$_epcf_age" -le "$projection_fresh_age_seconds" ]; then
      return 0
    fi
  else
    _epcf_age="unknown"
  fi

  _epcf_waited=0
  while [ "$_epcf_waited" -lt "$projection_wait_seconds" ]; do
    sleep 1
    _epcf_waited=$((_epcf_waited + 1))
    _epcf_link=$(readlink_target "$_epcf_data_link")
    _epcf_after=$(config_fingerprint "$config_file") || _epcf_after=""
    if [ "$_epcf_link" != "$_epcf_initial_link" ] || [ "$_epcf_after" != "$_epcf_current" ]; then
      echo "INFO: projected config changed after ${_epcf_waited}s; proceeding with reconfigure" >&2
      return 0
    fi
  done

  echo "ERROR: projected config did not refresh after ${projection_wait_seconds}s: dataLink='${_epcf_initial_link}', age='${_epcf_age}', mounted='${_epcf_current}', retry-safe: yes" >&2
  return 1
}

apply_config_diff() {
  engine_dump=$(redis-cli ${REDIS_CLI_TLS_CMD:-} -p "$service_port" $auth_arg CONFIG GET '*' 2>/dev/null) || {
    echo "ERROR: redis-cli CONFIG GET * failed" >&2
    return 1
  }

  _acd_rc=0
  _rcf_applied_count=0
  while IFS= read -r line; do
    case "$line" in '#'*|''|include\ *|loadmodule\ *) continue ;; esac
    key="${line%% *}"
    value="${line#* }"
    [ "$key" != "$value" ] || continue
    value=$(normalize_value "$value")

    is_dynamic "$key" || continue
    engine_has_key "$key" || continue

    current=$(engine_value "$key")
    values_match "$value" "$current" && continue

    reload_parameter "$key" "$value" || { _acd_rc=$?; echo "ERROR: CONFIG SET $key failed" >&2; continue; }
    verify_engine_state "$key" "$value" || { _acd_rc=1; echo "ERROR: post-set verification for $key failed" >&2; }
    _rcf_applied_count=$((_rcf_applied_count + 1))
  done < "$config_file"

  echo "INFO: applied $_rcf_applied_count parameter(s)" >&2
  return "$_acd_rc"
}

reconfigure_from_config_file() {
  if [ ! -f "$config_file" ]; then
    echo "ERROR: rendered config not found: $config_file" >&2
    return 1
  fi

  ensure_projected_config_fresh || return 1
  apply_config_diff
}

${__SOURCED__:+false} : || return 0

init_reconfigure_env
reconfigure_from_config_file
exit $?
