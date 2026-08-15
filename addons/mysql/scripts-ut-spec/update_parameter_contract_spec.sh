# shellcheck shell=bash

Describe "MySQL dynamic parameter update contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  script_path() {
    printf "%s/addons/mysql/scripts/update-parameter.sh" "$(repo_root)"
  }

  prepare_mysql_shim() {
    tmp_dir=$(mktemp -d)
    query_file="${tmp_dir}/query"
    call_file="${tmp_dir}/called"

    cat >"${tmp_dir}/mysql" <<'SH'
#!/bin/sh
: >"${MYSQL_CALL_FILE:?}"
for arg do
  query=$arg
done
printf '%s\n' "$query" >"${MYSQL_QUERY_FILE:?}"

if [ "${MYSQL_SHIM_ERROR:-}" = "true" ]; then
  printf '%s\n' 'ERROR 1238 (HY000): Variable is read only' >&2
  exit 1
fi
SH
    chmod +x "${tmp_dir}/mysql"
  }

  cleanup_mysql_shim() {
    rm -rf "${tmp_dir}"
  }

  run_parameter_update() {
    param_name=$1
    param_value=$2
    shim_error=${3:-false}
    prepare_mysql_shim || return

    PATH="${tmp_dir}:${PATH}" \
      MYSQL_CALL_FILE="${call_file}" \
      MYSQL_QUERY_FILE="${query_file}" \
      MYSQL_SHIM_ERROR="${shim_error}" \
      MYSQL_ADMIN_USER="root" \
      MYSQL_ADMIN_PASSWORD="root password" \
      bash "$(script_path)" "${param_name}" "${param_value}"
    rc=$?

    if [ -f "${query_file}" ]; then
      cat "${query_file}"
    fi
    cleanup_mysql_shim
    return "${rc}"
  }

  reject_invalid_parameter_name() {
    prepare_mysql_shim || return

    PATH="${tmp_dir}:${PATH}" \
      MYSQL_CALL_FILE="${call_file}" \
      MYSQL_QUERY_FILE="${query_file}" \
      MYSQL_ADMIN_USER="root" \
      MYSQL_ADMIN_PASSWORD="root password" \
      bash "$(script_path)" 'max_connections; SELECT 1' '100' >/dev/null 2>&1
    rc=$?

    [ "${rc}" -ne 0 ] && [ ! -e "${call_file}" ]
    result=$?
    cleanup_mysql_shim
    return "${result}"
  }

  It "escapes apostrophes before embedding a string value in SQL"
    When call run_parameter_update sql_mode "O'Reilly"
    The status should be success
    The output should include "SET GLOBAL sql_mode = 'O''Reilly';"
  End

  It "rejects an invalid parameter name before invoking mysql"
    When call reject_invalid_parameter_name
    The status should be success
  End

  It "returns failure for non-authentication MySQL errors"
    When call run_parameter_update read_only ON true
    The status should be failure
    The output should include "ERROR 1238 (HY000): Variable is read only"
  End
End
