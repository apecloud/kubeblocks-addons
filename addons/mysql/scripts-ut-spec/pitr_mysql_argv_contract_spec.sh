# shellcheck shell=sh

Describe "MySQL PITR archive client argv contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/mysql" "$(repo_root)"
  }

  run_initial_mysql_probe() {
    tmp_dir=$(mktemp -d)
    argv_file="$tmp_dir/argv"

    cat >"$tmp_dir/mysql" <<'SH'
#!/bin/sh
index=0
for arg do
  printf '%s=%s\n' "$index" "$arg"
  index=$((index + 1))
done >"${MYSQL_ARGV_FILE:?}"
SH
    chmod +x "$tmp_dir/mysql"

    PATH="$tmp_dir:$PATH" \
      MYSQL_ARGV_FILE="$argv_file" \
      MYSQL_ADMIN_PASSWORD='' \
      DP_DB_USER='archive user[*]' \
      DP_DB_PASSWORD='alpha beta[*]' \
      DP_DB_HOST='mysql host[*]' \
      DP_DB_PORT=3307 \
      DP_DATASAFED_BIN_PATH=/bin \
      VOLUME_DATA_DIR="$tmp_dir/data" \
      DP_TARGET_POD_NAME=mysql-0 \
      bash "$(chart_path)/dataprotection/mysql-pitr-backup.sh" >/dev/null 2>&1
    rc=$?

    if [ "$rc" -eq 1 ]; then
      cat "$argv_file"
    fi
    rm -rf "$tmp_dir"
    [ "$rc" -eq 1 ]
  }

  direct_mysql_calls_without_configured_port() {
    awk '/mysql -u/ && index($0, "-P\"${DP_DB_PORT}\"") == 0' \
      "$(chart_path)/dataprotection/mysql-pitr-backup.sh"
  }

  It "preserves the initial archive connection identity as literal mysql arguments"
    When call run_initial_mysql_probe
    The status should be success
    The output should include "0=--user=archive user[*]"
    The output should include "1=--host=mysql host[*]"
    The output should include "2=--port=3307"
    The output should include "3=--skip-column-names"
    The output should include "4=--execute=SHOW VARIABLES LIKE 'log_bin_basename';"
    The lines of output should equal 5
  End

  It "passes the configured port to every direct cleanup mysql call"
    When call direct_mysql_calls_without_configured_port
    The output should equal ""
  End
End
