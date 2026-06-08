#!/bin/sh

init_reconfigure_env() {
  config_file="/etc/conf/redis.conf"
  dynamic_allowlist="${DYNAMIC_ALLOWLIST:-}"
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

reconfigure_from_config_file() {
  case "${KB_CONFIG_FILES_UPDATED:-}" in
    *redis.conf*) ;;
    *) return 0 ;;
  esac

  if [ ! -f "$config_file" ]; then
    echo "ERROR: rendered config not found: $config_file" >&2
    return 1
  fi

  engine_dump=$(redis-cli ${REDIS_CLI_TLS_CMD:-} -p "$service_port" $auth_arg CONFIG GET '*' 2>/dev/null) || {
    echo "ERROR: redis-cli CONFIG GET * failed" >&2
    return 1
  }

  rc=0
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

    reload_parameter "$key" "$value" || { rc=$?; echo "ERROR: CONFIG SET $key failed" >&2; continue; }
    verify_engine_state "$key" "$value" || { rc=1; echo "ERROR: post-set verification for $key failed" >&2; }
  done < "$config_file"
  return "$rc"
}

${__SOURCED__:+false} : || return 0

init_reconfigure_env
reconfigure_from_config_file
exit $?
