#!/bin/sh

init_reconfigure_env() {
  config_file="/etc/conf/redis.conf"
  dynamic_allowlist="${DYNAMIC_ALLOWLIST:-}"
  service_port=${SERVICE_PORT:-6379}
  wait_timeout=${RECONFIGURE_WAIT_TIMEOUT:-180}
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
  if [ "$_vf_actual" != "$2" ]; then
    echo "INFO: CONFIG SET $1 applied; engine reports '$_vf_actual' (rendered '$2')" >&2
  fi
  return 0
}

reload_parameter() {
  /scripts/reload-parameter.sh "$@"
}

config_file_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$config_file" | awk '{print $1}'
  else
    shasum -a 256 "$config_file" | awk '{print $1}'
  fi
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
    [ "$value" != "$current" ] || continue

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

  _rcf_hash=$(config_file_hash)
  echo "INFO: reconfigure start, config hash=$_rcf_hash" >&2

  _rcf_timeout=${wait_timeout:-90}
  _rcf_elapsed=0
  while [ "$_rcf_elapsed" -lt "$_rcf_timeout" ]; do
    sleep 2
    _rcf_elapsed=$((_rcf_elapsed + 2))
    _rcf_new_hash=$(config_file_hash)
    if [ "$_rcf_new_hash" != "$_rcf_hash" ]; then
      echo "INFO: config file updated after ${_rcf_elapsed}s (new hash=$_rcf_new_hash), applying" >&2
      apply_config_diff
      return $?
    fi
  done

  if [ "$_rcf_timeout" -gt 0 ]; then
    echo "INFO: config file unchanged after ${_rcf_timeout}s" >&2
  fi

  apply_config_diff
  _rcf_rc=$?

  if [ "$_rcf_applied_count" -eq 0 ] && [ "$_rcf_timeout" -gt 0 ]; then
    echo "ERROR: watch timed out with 0 params applied, failing to prevent false green" >&2
    return 1
  fi
  return "$_rcf_rc"
}

${__SOURCED__:+false} : || return 0

init_reconfigure_env
reconfigure_from_config_file
exit $?
