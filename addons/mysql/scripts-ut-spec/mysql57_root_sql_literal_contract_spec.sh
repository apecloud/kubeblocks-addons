# shellcheck shell=bash

Describe "MySQL 5.7 root credential SQL literal contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  script_path() {
    printf "%s/addons/mysql/scripts/docker-entrypoint-5.7.sh" "$(repo_root)"
  }

  run_root_setup() {
    tmp_dir=$(mktemp -d)
    sql_file="$tmp_dir/sql"

    MYSQL_INITDB_SKIP_TZINFO=1 \
      MYSQL_ROOT_HOST="db'host[*]" \
      MYSQL_ROOT_PASSWORD="pa'ss[*]" \
      MYSQL_DATABASE='' \
      MYSQL_USER='' \
      MYSQL_PASSWORD='' \
      SQL_FILE="$sql_file" \
      bash -c '
        source "$1"
        docker_process_sql() {
          cat >"${SQL_FILE:?}"
        }
        docker_setup_db
      ' bash "$(script_path)" >/dev/null 2>&1
    rc=$?

    cat "$sql_file"
    rm -rf "$tmp_dir"
    return "$rc"
  }

  It "escapes root host and password before embedding them in initialization SQL"
    When call run_root_setup
    The status should be success
    The output should include "CREATE USER 'root'@'db''host[*]' IDENTIFIED BY 'pa''ss[*]' ;"
    The output should include "ALTER USER 'root'@'localhost' IDENTIFIED BY 'pa''ss[*]' ;"
  End
End
