# shellcheck shell=sh

Describe "MySQL PITR restore replay client argv contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/mysql" "$(repo_root)"
  }

  run_binlog_replay() {
    tmp_dir=$(mktemp -d)
    argv_file="$tmp_dir/argv"

    cat >"$tmp_dir/DP_log" <<'SH'
#!/bin/sh
exit 0
SH
    cat >"$tmp_dir/mysqlbinlog" <<'SH'
#!/bin/sh
printf '%s\n' 'SELECT 1;'
SH
    cat >"$tmp_dir/mysql" <<'SH'
#!/bin/sh
index=0
for arg do
  printf '%s=%s\n' "$index" "$arg"
  index=$((index + 1))
done >"${MYSQL_ARGV_FILE:?}"
cat >/dev/null
SH
    cat >"$tmp_dir/wal-g" <<'SH'
#!/bin/sh
WALG_MYSQL_BINLOG_END_TS='2026-08-15T00:00:00Z' \
  WALG_MYSQL_CURRENT_BINLOG='/tmp/mysql binlog[*]' \
  sh -c "${WALG_MYSQL_BINLOG_REPLAY_COMMAND:?}"
SH
    chmod +x "$tmp_dir/DP_log" "$tmp_dir/mysqlbinlog" "$tmp_dir/mysql" "$tmp_dir/wal-g"

    PATH="$tmp_dir:$PATH" \
      MYSQL_ARGV_FILE="$argv_file" \
      MYSQL_ADMIN_USER='restore user[*]' \
      MYSQL_ADMIN_PASSWORD='alpha beta[*]' \
      DP_DB_HOST='mysql host[*]' \
      DP_DB_PORT=3307 \
      DP_DATASAFED_BIN_PATH=/bin \
      DP_BACKUP_BASE_PATH=/backup \
      PITR_DIR="$tmp_dir/pitr" \
      DP_BASE_BACKUP_START_TIME='2026-08-14T00:00:00Z' \
      DP_RESTORE_TIME='2026-08-15T00:00:00Z' \
      bash "$(chart_path)/dataprotection/mysql-pitr-restore.sh" >/dev/null 2>&1
    rc=$?

    if [ -f "$argv_file" ]; then
      cat "$argv_file"
    fi
    rm -rf "$tmp_dir"
    return "$rc"
  }

  It "preserves restore connection identity as literal mysql arguments"
    When call run_binlog_replay
    The status should be success
    The output should include "0=--user=restore user[*]"
    The output should include "1=--host=mysql host[*]"
    The output should include "2=--port=3307"
    The lines of output should equal 3
  End
End
