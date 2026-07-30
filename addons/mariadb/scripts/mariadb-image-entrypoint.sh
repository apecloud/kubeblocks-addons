#!/bin/bash
set -euo pipefail

readonly IMAGE_INIT_IN_PROGRESS_MARKER=".kb-mariadb-image-init-in-progress"
readonly IMAGE_INIT_COMPLETE_MARKER=".kb-mariadb-image-init-complete"
readonly DEFAULT_TEMP_SERVER_START_TIMEOUT_SECONDS=120

validate_mariadb_data_dir() {
  local data_dir="${1:-}"
  case "${data_dir}" in
    ""|"/"|"/var"|"/var/lib")
      echo "unsafe MariaDB data directory for fresh-init recovery: '${data_dir}'" >&2
      return 1
      ;;
  esac
  case "${data_dir}" in
    /*) ;;
    *)
      echo "MariaDB data directory must be absolute for fresh-init recovery: '${data_dir}'" >&2
      return 1
      ;;
  esac
}

recover_partial_mariadb_image_init() {
  local data_dir="$1"
  local in_progress="${data_dir}/${IMAGE_INIT_IN_PROGRESS_MARKER}"
  local complete="${data_dir}/${IMAGE_INIT_COMPLETE_MARKER}"

  validate_mariadb_data_dir "${data_dir}" || return 1
  [ -f "${in_progress}" ] || return 0

  if [ -f "${complete}" ]; then
    rm -f "${in_progress}" || return 1
    return 0
  fi

  echo "recovering interrupted addon-owned MariaDB fresh initialization" >&2
  find "${data_dir}" -mindepth 1 -maxdepth 1 \
    ! -name "${IMAGE_INIT_IN_PROGRESS_MARKER}" \
    ! -name "runtime-overrides.cnf" \
    ! -name "runtime-overrides.d" \
    ! -name "log" \
    ! -name "binlog" \
    ! -name "tmp" \
    -exec rm -rf -- {} + || return 1
  rm -f "${in_progress}" || return 1
}

validate_temp_server_start_timeout() {
  local timeout="$1"
  case "${timeout}" in
    *[!0-9]*|"")
      echo "invalid MariaDB temporary-server startup timeout: '${timeout}'" >&2
      return 1
      ;;
  esac
  if [ "${timeout}" -lt 31 ] || [ "${timeout}" -gt 300 ]; then
    echo "MariaDB temporary-server startup timeout must be between 31 and 300 seconds: '${timeout}'" >&2
    return 1
  fi
}

prepare_mariadb_image_entrypoint() {
  local source_path="$1"
  local target_path="$2"
  local timeout="${3:-${DEFAULT_TEMP_SERVER_START_TIMEOUT_SECONDS}}"
  local tmp_path="${target_path}.tmp.$$"

  validate_temp_server_start_timeout "${timeout}" || return 1
  if [ ! -r "${source_path}" ]; then
    echo "MariaDB image entrypoint is missing or unreadable: '${source_path}'" >&2
    return 1
  fi

  rm -f "${tmp_path}"
  if ! awk \
    -v timeout="${timeout}" \
    -v in_progress="${IMAGE_INIT_IN_PROGRESS_MARKER}" \
    -v complete="${IMAGE_INIT_COMPLETE_MARKER}" '
      /^[[:space:]]*for i in \{30\.\.0\}; do[[:space:]]*$/ {
        timeout_sites++
        match($0, /^[[:space:]]*/)
        indent = substr($0, 1, RLENGTH)
        print indent "for ((i = " timeout "; i >= 0; i--)); do"
        next
      }
      /^[[:space:]]*docker_mariadb_init "\$@"[[:space:]]*$/ {
        init_sites++
        print
        match($0, /^[[:space:]]*/)
        indent = substr($0, 1, RLENGTH)
        print indent "touch \"$DATADIR/" complete "\""
        print indent "rm -f \"$DATADIR/" in_progress "\""
        next
      }
      { print }
      END {
        if (timeout_sites != 1 || init_sites != 1) {
          print "unsupported MariaDB image entrypoint contract: expected one 30-second loop and one docker_mariadb_init call; found timeout=" timeout_sites ", init=" init_sites > "/dev/stderr"
          exit 42
        }
      }
    ' "${source_path}" > "${tmp_path}"; then
    rm -f "${tmp_path}"
    return 1
  fi
  chmod 0555 "${tmp_path}" || return 1
  mv -f "${tmp_path}" "${target_path}" || return 1
}

run_mariadb_image_entrypoint() {
  local data_dir="$1"
  shift
  local source_path="/usr/local/bin/docker-entrypoint.sh"
  local target_path="/tmp/kb-mariadb-docker-entrypoint.sh"
  local timeout="${MARIADB_TEMP_SERVER_START_TIMEOUT_SECONDS:-${DEFAULT_TEMP_SERVER_START_TIMEOUT_SECONDS}}"

  validate_mariadb_data_dir "${data_dir}" || return 1
  prepare_mariadb_image_entrypoint "${source_path}" "${target_path}" "${timeout}" || return 1
  if [ ! -d "${data_dir}/mysql" ] && [ ! -f "${data_dir}/${IMAGE_INIT_COMPLETE_MARKER}" ]; then
    touch "${data_dir}/${IMAGE_INIT_IN_PROGRESS_MARKER}" || return 1
  fi
  exec "${target_path}" "$@"
}

main() {
  local mode="${1:-}"
  case "${mode}" in
    recover)
      [ "$#" -eq 2 ] || {
        echo "usage: $0 recover DATA_DIR" >&2
        return 2
      }
      recover_partial_mariadb_image_init "$2"
      ;;
    run)
      [ "$#" -ge 3 ] || {
        echo "usage: $0 run DATA_DIR mariadbd [args...]" >&2
        return 2
      }
      shift
      run_mariadb_image_entrypoint "$@"
      ;;
    *)
      echo "usage: $0 {recover DATA_DIR|run DATA_DIR mariadbd [args...]}" >&2
      return 2
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
