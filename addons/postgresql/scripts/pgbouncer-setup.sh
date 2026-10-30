#!/bin/sh

pgbouncer_template_conf_file="/opt/pgbouncer-template/pgbouncer.ini"
pgbouncer_conf_dir="/etc/pgbouncer"
pgbouncer_conf_file="${pgbouncer_conf_dir}/pgbouncer.ini"
pgbouncer_user_list_file="${pgbouncer_conf_dir}/userlist.txt"
pgbouncer_bin="/usr/bin/pgbouncer"

pgbouncer_log() {
  printf '%s\n' "pgbouncer-setup: $*" >&2
}

validate_runtime_inputs() {
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
}

build_pgbouncer_conf() {
  umask 077
  validate_runtime_inputs || return 1
  mkdir -p "$pgbouncer_conf_dir" || return 1

  pgbouncer_escaped_username=$(printf '%s' "$POSTGRESQL_USERNAME" | sed 's/"/""/g')
  pgbouncer_escaped_password=$(printf '%s' "$POSTGRESQL_PASSWORD" | sed 's/"/""/g')
  pgbouncer_generated_file=$(mktemp "${pgbouncer_conf_dir}/.pgbouncer.ini.XXXXXX") || return 1
  pgbouncer_user_list_tmp=$(mktemp "${pgbouncer_conf_dir}/.userlist.txt.XXXXXX") || {
    rm -f "$pgbouncer_generated_file"
    return 1
  }

  if ! printf '%%include %s\n\n[databases]\n' "$pgbouncer_template_conf_file" > "$pgbouncer_generated_file" ||
    ! printf 'postgres=host=%s port=%s dbname=postgres\n' "$pgbouncer_backend_host" "$pgbouncer_backend_port" >> "$pgbouncer_generated_file" ||
    ! printf '*=host=%s port=%s\n' "$pgbouncer_backend_host" "$pgbouncer_backend_port" >> "$pgbouncer_generated_file" ||
    ! chmod 600 "$pgbouncer_generated_file" ||
    ! printf '"%s" "%s"\n' "$pgbouncer_escaped_username" "$pgbouncer_escaped_password" > "$pgbouncer_user_list_tmp" ||
    ! chmod 600 "$pgbouncer_user_list_tmp"; then
    rm -f "$pgbouncer_generated_file" "$pgbouncer_user_list_tmp"
    return 1
  fi

  if ! mv -f "$pgbouncer_user_list_tmp" "$pgbouncer_user_list_file" ||
    ! mv -f "$pgbouncer_generated_file" "$pgbouncer_conf_file"; then
    rm -f "$pgbouncer_generated_file" "$pgbouncer_user_list_tmp"
    return 1
  fi
}

start_pgbouncer() {
  exec "$pgbouncer_bin" "$pgbouncer_conf_file"
}

main() {
  build_pgbouncer_conf || return 1
  start_pgbouncer
}

${__SOURCED__:+false} : || return 0

main
