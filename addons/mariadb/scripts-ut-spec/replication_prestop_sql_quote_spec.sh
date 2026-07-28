# shellcheck shell=bash

Describe "replication preStop SQL literal quoting"
  prestop_file() {
    printf "%s/addons/mariadb/scripts/replication-prestop.sh" "${SHELLSPEC_CWD:?}"
  }

  extract_function_from() {
    source_file="$1"
    function_name="$2"
    awk -v function_name="${function_name}" '
      $0 ~ "^[[:space:]]*" function_name "\\(\\)[[:space:]]*\\{" { inside = 1 }
      inside {
        print
        line = $0
        opens = gsub(/\{/, "", line)
        closes = gsub(/\}/, "", line)
        depth += opens - closes
        if (depth == 0) exit
      }
      END { if (!inside) exit 1 }
    ' "${source_file}"
  }

  run_quote() {
    work_dir="$(mktemp -d)"
    harness="${work_dir}/quote.sh"
    {
      printf '%s\n' '#!/bin/sh'
      extract_function_from "$(prestop_file)" prestop_sql_quote
      printf '%s\n' 'prestop_sql_quote "$1"'
    } > "${harness}"
    sh "${harness}" "$1"
    rc=$?
    rm -rf "${work_dir}"
    return "${rc}"
  }

  run_lock_case() {
    mode="$1"
    work_dir="$(mktemp -d)"
    harness="${work_dir}/lock.sh"
    capture="${work_dir}/capture"
    {
      printf '%s\n' '#!/bin/sh'
      extract_function_from "$(prestop_file)" prestop_sql_quote
      extract_function_from "$(prestop_file)" lock_local_root_for_prestop
      cat <<'HARNESS'
prestop_log() { :; }
run_sql() {
  printf 'mode=%s\n%s\n' "$2" "$3" >> "${CAPTURE}"
}
MARIADB_ROOT_USER="us\\er'one"
MARIADB_ROOT_PASSWORD="pa\\ss'end\\"
export MARIADB_ROOT_USER MARIADB_ROOT_PASSWORD
lock_local_root_for_prestop "quote-contract" "$1"
cat "${CAPTURE}"
HARNESS
    } > "${harness}"
    CAPTURE="${capture}" sh "${harness}" "${mode}"
    rc=$?
    rm -rf "${work_dir}"
    return "${rc}"
  }

  It "escapes embedded and trailing backslashes before doubling quotes"
    When call run_quote "a\\b'c\\"
    The status should be success
    The output should eq "a\\\\b''c\\\\"
  End

  It "uses the shared quoting contract in the socket fence path"
    When call run_lock_case socket
    The status should be success
    The output should include "mode=socket"
    The output should include "CREATE USER IF NOT EXISTS 'us\\\\er''one'@'localhost'"
    The output should include "IDENTIFIED BY 'pa\\\\ss''end\\\\'"
  End

  It "uses the shared quoting contract in the TCP fence path"
    When call run_lock_case tcp
    The status should be success
    The output should include "mode=tcp"
    The output should include "ALTER USER 'us\\\\er''one'@'127.0.0.1' IDENTIFIED BY 'pa\\\\ss''end\\\\'"
  End
End
