#!/bin/sh

pgbouncer_template_conf_file="/opt/pgbouncer-template/pgbouncer.ini"
pgbouncer_conf_dir="/etc/pgbouncer"
pgbouncer_log_dir="/var/log/pgbouncer"
pgbouncer_tmp_dir="/var/run/pgbouncer"
pgbouncer_conf_file="${pgbouncer_conf_dir}/pgbouncer.ini"
pgbouncer_user_list_file="${pgbouncer_conf_dir}/userlist.txt"

build_pgbouncer_conf() {
  backend_host="${POSTGRESQL_HOST:-}"
  backend_port="${POSTGRESQL_PORT:-}"

  if [ -z "${POSTGRESQL_USERNAME:-}" ] || [ -z "${POSTGRESQL_PASSWORD:-}" ] ||
    [ -z "$backend_host" ] || [ -z "$backend_port" ]; then
    echo "POSTGRESQL_USERNAME, POSTGRESQL_PASSWORD, POSTGRESQL_HOST or POSTGRESQL_PORT is not set. Exiting..."
    return 1
  fi

  credentials="${POSTGRESQL_USERNAME}${POSTGRESQL_PASSWORD}"
  sanitized_credentials=$(printf '%s' "$credentials" | tr -d '\r\n')
  if [ "$credentials" != "$sanitized_credentials" ]; then
    echo "PostgreSQL credentials contain an unsupported line break. Exiting..."
    return 1
  fi
  case "$backend_host" in
    *[!A-Za-z0-9.-]*)
      echo "PostgreSQL backend host contains unsupported characters. Exiting..."
      return 1
      ;;
  esac
  case "$backend_port" in
    ''|*[!0-9]*)
      echo "PostgreSQL backend port is invalid. Exiting..."
      return 1
      ;;
  esac

  escaped_username=$(printf '%s' "$POSTGRESQL_USERNAME" | sed 's/"/""/g')
  escaped_password=$(printf '%s' "$POSTGRESQL_PASSWORD" | sed 's/"/""/g')

  mkdir -p "$pgbouncer_conf_dir" "$pgbouncer_log_dir" "$pgbouncer_tmp_dir" || return $?
  cp "$pgbouncer_template_conf_file" "$pgbouncer_conf_file" || return $?
  # ConfigMap projections are read-only (0444), and cp preserves that mode.
  # Make the generated copy writable before appending the backend routes.
  chmod 600 "$pgbouncer_conf_file" || return $?
  printf '"%s" "%s"\n' "$escaped_username" "$escaped_password" > "$pgbouncer_user_list_file" || return $?
  # shellcheck disable=SC2129
  printf '\n[databases]\n' >> "$pgbouncer_conf_file" || return $?
  printf 'postgres=host=%s port=%s dbname=postgres\n' "$backend_host" "$backend_port" >> "$pgbouncer_conf_file" || return $?
  printf '*=host=%s port=%s\n' "$backend_host" "$backend_port" >> "$pgbouncer_conf_file" || return $?
  chmod 644 "$pgbouncer_conf_file" || return $?
  chmod 600 "$pgbouncer_user_list_file" || return $?
}

start_pgbouncer() {
  exec /usr/bin/pgbouncer "$pgbouncer_conf_file"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
main() {
  build_pgbouncer_conf || return $?
  start_pgbouncer
}

${__SOURCED__:+false} : || return 0

main
