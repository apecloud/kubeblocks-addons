#!/bin/sh

pgbouncer_template_conf_file="/opt/pgbouncer-template/pgbouncer.ini"
pgbouncer_conf_dir="/etc/pgbouncer"
pgbouncer_conf_file="${pgbouncer_conf_dir}/pgbouncer.ini"
pgbouncer_user_list_file="${pgbouncer_conf_dir}/userlist.txt"
pgbouncer_bin="/usr/bin/pgbouncer"

pgbouncer_log() {
  printf '%s\n' "pgbouncer-setup: $*" >&2
}

validate_pool_integer() {
  pgbouncer_integer_name="$1"
  pgbouncer_integer_value="$2"
  pgbouncer_integer_allow_zero="$3"

  case "$pgbouncer_integer_value" in
    ''|*[!0-9]*|0[0-9]*)
      pgbouncer_log "$pgbouncer_integer_name must be a canonical decimal integer"
      return 1
      ;;
  esac
  if [ "$pgbouncer_integer_allow_zero" != "true" ] && [ "$pgbouncer_integer_value" = "0" ]; then
    pgbouncer_log "$pgbouncer_integer_name must be greater than zero"
    return 1
  fi
  if [ "${#pgbouncer_integer_value}" -gt 6 ]; then
    pgbouncer_log "$pgbouncer_integer_name is outside the supported range"
    return 1
  fi
}

validate_pgbouncer_template() {
  pgbouncer_expected_keys="listen_addr listen_port unix_socket_dir unix_socket_mode auth_file auth_type auth_user auth_query auth_dbname admin_users stats_users pool_mode client_tls_sslmode server_tls_sslmode ignore_startup_parameters max_client_conn default_pool_size min_pool_size reserve_pool_size reserve_pool_timeout max_db_connections max_user_connections server_idle_timeout server_lifetime query_wait_timeout client_idle_timeout"
  pgbouncer_seen_keys=" "
  pgbouncer_seen_section="false"

  while IFS= read -r pgbouncer_template_line || [ -n "$pgbouncer_template_line" ]; do
    pgbouncer_trimmed_line=$(printf '%s' "$pgbouncer_template_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$pgbouncer_trimmed_line" in
      ''|';'*|'#'*)
        continue
        ;;
      '[pgbouncer]')
        if [ "$pgbouncer_seen_section" = "true" ]; then
          pgbouncer_log "rendered configuration contains a duplicate [pgbouncer] section"
          return 1
        fi
        pgbouncer_seen_section="true"
        continue
        ;;
      '['*']')
        pgbouncer_log "rendered configuration contains an unexpected section"
        return 1
        ;;
      *=*)
        ;;
      *)
        pgbouncer_log "rendered configuration contains an invalid line"
        return 1
        ;;
    esac

    if [ "$pgbouncer_seen_section" != "true" ]; then
      pgbouncer_log "rendered configuration contains a setting before [pgbouncer]"
      return 1
    fi
    pgbouncer_template_key=$(printf '%s' "${pgbouncer_trimmed_line%%=*}" | sed 's/[[:space:]]*$//')
    pgbouncer_template_value=$(printf '%s' "${pgbouncer_trimmed_line#*=}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case " $pgbouncer_expected_keys " in
      *" $pgbouncer_template_key "*)
        ;;
      *)
        pgbouncer_log "rendered configuration contains unsupported setting: $pgbouncer_template_key"
        return 1
        ;;
    esac
    case "$pgbouncer_seen_keys" in
      *" $pgbouncer_template_key "*)
        pgbouncer_log "rendered configuration contains duplicate setting: $pgbouncer_template_key"
        return 1
        ;;
    esac
    pgbouncer_seen_keys="${pgbouncer_seen_keys}${pgbouncer_template_key} "

    pgbouncer_managed_value=""
    case "$pgbouncer_template_key" in
      listen_addr)
        pgbouncer_managed_value="*"
        ;;
      listen_port)
        pgbouncer_managed_value="6432"
        ;;
      unix_socket_dir)
        pgbouncer_managed_value="/tmp"
        ;;
      unix_socket_mode)
        pgbouncer_managed_value="0770"
        ;;
      auth_file)
        pgbouncer_managed_value="/etc/pgbouncer/userlist.txt"
        ;;
      auth_type)
        pgbouncer_managed_value="md5"
        ;;
      auth_user|auth_dbname|admin_users|stats_users)
        pgbouncer_managed_value="postgres"
        ;;
      auth_query)
        pgbouncer_managed_value='SELECT rolname, CASE WHEN rolvaliduntil IS NOT NULL AND rolvaliduntil < pg_catalog.now() THEN NULL ELSE rolpassword END FROM pg_catalog.pg_authid WHERE rolname=$1 AND rolcanlogin'
        ;;
      client_tls_sslmode|server_tls_sslmode)
        pgbouncer_managed_value="disable"
        ;;
      ignore_startup_parameters)
        pgbouncer_managed_value="extra_float_digits"
        ;;
      reserve_pool_timeout)
        pgbouncer_managed_value="5"
        ;;
      server_idle_timeout)
        pgbouncer_managed_value="600"
        ;;
      server_lifetime)
        pgbouncer_managed_value="3600"
        ;;
      query_wait_timeout)
        pgbouncer_managed_value="120"
        ;;
      client_idle_timeout)
        pgbouncer_managed_value="0"
        ;;
      pool_mode)
        case "$pgbouncer_template_value" in
          session|transaction|statement)
            ;;
          *)
            pgbouncer_log "pool_mode must be session, transaction, or statement"
            return 1
            ;;
        esac
        ;;
      max_client_conn|default_pool_size)
        validate_pool_integer "$pgbouncer_template_key" "$pgbouncer_template_value" false || return 1
        ;;
      min_pool_size|reserve_pool_size|max_db_connections|max_user_connections)
        validate_pool_integer "$pgbouncer_template_key" "$pgbouncer_template_value" true || return 1
        ;;
    esac
    if [ -n "$pgbouncer_managed_value" ] && [ "$pgbouncer_template_value" != "$pgbouncer_managed_value" ]; then
      pgbouncer_log "managed setting cannot be overridden: $pgbouncer_template_key"
      return 1
    fi
  done < "$pgbouncer_template_conf_file"

  if [ "$pgbouncer_seen_section" != "true" ]; then
    pgbouncer_log "rendered configuration is missing [pgbouncer]"
    return 1
  fi
  for pgbouncer_required_key in $pgbouncer_expected_keys; do
    case "$pgbouncer_seen_keys" in
      *" $pgbouncer_required_key "*)
        ;;
      *)
        pgbouncer_log "rendered configuration is missing setting: $pgbouncer_required_key"
        return 1
        ;;
    esac
  done
}

validate_component_inputs() {
  pgbouncer_backend_host="${POSTGRESQL_HOST:-}"
  pgbouncer_backend_port="${POSTGRESQL_PORT:-}"

  if [ -z "${POSTGRESQL_USERNAME:-}" ] || [ -z "${POSTGRESQL_PASSWORD:-}" ] ||
    [ -z "$pgbouncer_backend_host" ] || [ -z "$pgbouncer_backend_port" ]; then
    pgbouncer_log "POSTGRESQL_USERNAME, POSTGRESQL_PASSWORD, POSTGRESQL_HOST or POSTGRESQL_PORT is not set"
    return 1
  fi

  pgbouncer_credentials="${POSTGRESQL_USERNAME}${POSTGRESQL_PASSWORD}"
  pgbouncer_sanitized_credentials=$(printf '%s' "$pgbouncer_credentials" | tr -d '\r\n')
  if [ "$pgbouncer_credentials" != "$pgbouncer_sanitized_credentials" ]; then
    pgbouncer_log "PostgreSQL credentials contain an unsupported line break"
    return 1
  fi

  case "$pgbouncer_backend_host" in
    *[!A-Za-z0-9.-]*)
      pgbouncer_log "PostgreSQL backend host contains unsupported characters"
      return 1
      ;;
  esac
  case "$pgbouncer_backend_port" in
    ''|*[!0-9]*)
      pgbouncer_log "PostgreSQL backend port is invalid"
      return 1
      ;;
  esac
  if [ "$pgbouncer_backend_port" -lt 1 ] || [ "$pgbouncer_backend_port" -gt 65535 ]; then
    pgbouncer_log "PostgreSQL backend port is outside 1..65535"
    return 1
  fi

  if [ ! -r "$pgbouncer_template_conf_file" ]; then
    pgbouncer_log "rendered PgBouncer configuration is not readable"
    return 1
  fi
  validate_pgbouncer_template || return 1
}

build_pgbouncer_conf() {
  umask 077
  validate_component_inputs || return 1
  mkdir -p "$pgbouncer_conf_dir" || return 1

  pgbouncer_escaped_username=$(printf '%s' "$POSTGRESQL_USERNAME" | sed 's/"/""/g')
  pgbouncer_escaped_password=$(printf '%s' "$POSTGRESQL_PASSWORD" | sed 's/"/""/g')
  pgbouncer_generated_file=$(mktemp "${pgbouncer_conf_dir}/.pgbouncer.ini.XXXXXX") || return 1
  pgbouncer_user_list_tmp=$(mktemp "${pgbouncer_conf_dir}/.userlist.txt.XXXXXX") || {
    rm -f "$pgbouncer_generated_file"
    return 1
  }

  if ! cp "$pgbouncer_template_conf_file" "$pgbouncer_generated_file" ||
    ! chmod 600 "$pgbouncer_generated_file" ||
    ! printf '"%s" "%s"\n' "$pgbouncer_escaped_username" "$pgbouncer_escaped_password" > "$pgbouncer_user_list_tmp" ||
    ! chmod 600 "$pgbouncer_user_list_tmp"; then
    rm -f "$pgbouncer_generated_file" "$pgbouncer_user_list_tmp"
    return 1
  fi

  # shellcheck disable=SC2129
  if ! printf '\n[databases]\n' >> "$pgbouncer_generated_file" ||
    ! printf 'postgres=host=%s port=%s dbname=postgres\n' "$pgbouncer_backend_host" "$pgbouncer_backend_port" >> "$pgbouncer_generated_file" ||
    ! printf '*=host=%s port=%s\n' "$pgbouncer_backend_host" "$pgbouncer_backend_port" >> "$pgbouncer_generated_file" ||
    ! mv -f "$pgbouncer_user_list_tmp" "$pgbouncer_user_list_file" ||
    ! mv -f "$pgbouncer_generated_file" "$pgbouncer_conf_file"; then
    rm -f "$pgbouncer_generated_file" "$pgbouncer_user_list_tmp"
    return 1
  fi
}

start_pgbouncer() {
  exec "$pgbouncer_bin" "$pgbouncer_conf_file"
}

# This is magic for shellspec ut framework. When this file is included from
# shellspec, __SOURCED__ is set and main must not run.
main() {
  build_pgbouncer_conf || return 1
  start_pgbouncer
}

${__SOURCED__:+false} : || return 0

main
