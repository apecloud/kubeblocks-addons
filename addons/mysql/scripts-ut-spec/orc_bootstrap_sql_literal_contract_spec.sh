# shellcheck shell=bash

Describe "MySQL ORC bootstrap SQL literal contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  script_path() {
    printf "%s/addons/mysql/scripts/init-mysql-instance-for-orc.sh" "$(repo_root)"
  }

  prepare_mysql_capture() {
    tmp_dir=$(mktemp -d)
    sql_file="$tmp_dir/sql"

    cat >"$tmp_dir/mysql" <<'SH'
#!/bin/sh
cat >"${MYSQL_SQL_FILE:?}"
SH
    cat >"$tmp_dir/date" <<'SH'
#!/bin/sh
printf '%s\n' '2026-08-15 00:00:00+00:00'
SH
    chmod +x "$tmp_dir/mysql" "$tmp_dir/date"
  }

  run_create_mysql_user() {
    prepare_mysql_capture

    PATH="$tmp_dir:$PATH" \
      MYSQL_SQL_FILE="$sql_file" \
      MYSQL_ROOT_USER="root" \
      MYSQL_ROOT_PASSWORD="root password" \
      ORC_TOPOLOGY_USER="orc'user" \
      ORC_TOPOLOGY_PASSWORD="pa'ss" \
      bash -c 'source "$1"; create_mysql_user >/dev/null' bash "$(script_path)"
    rc=$?

    cat "$sql_file"
    rm -rf "$tmp_dir"
    return "$rc"
  }

  run_change_master() {
    prepare_mysql_capture

    PATH="$tmp_dir:$PATH" \
      MYSQL_SQL_FILE="$sql_file" \
      MYSQL_MAJOR="8.0" \
      MYSQL_ROOT_USER="ro'ot" \
      MYSQL_ROOT_PASSWORD="root'pass" \
      bash -c 'source "$1"; change_master "mysql-0'"'"'host" >/dev/null' bash "$(script_path)"
    rc=$?

    cat "$sql_file"
    rm -rf "$tmp_dir"
    return "$rc"
  }

  It "escapes ORC topology credentials before embedding them in account SQL"
    When call run_create_mysql_user
    The status should be success
    The output should include "CREATE USER IF NOT EXISTS 'orc''user'@'%' IDENTIFIED BY 'pa''ss';"
    The output should include "ALTER USER 'orc''user'@'%' IDENTIFIED BY 'pa''ss';"
  End

  It "escapes replication host and credentials before embedding them in CHANGE MASTER SQL"
    When call run_change_master
    The status should be success
    The output should include "MASTER_HOST='mysql-0''host',"
    The output should include "MASTER_USER='ro''ot',"
    The output should include "MASTER_PASSWORD='root''pass';"
  End
End
