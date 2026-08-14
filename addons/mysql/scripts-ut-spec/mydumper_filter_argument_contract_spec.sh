# shellcheck shell=bash

Describe "MySQL mydumper filter argument contract"
  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  chart_path() {
    printf "%s/addons/mysql" "$(repo_root)"
  }

  write_mock_tools() {
    mock_bin=$1

    mkdir -p "${mock_bin}" || return 1
    printf '%s\n' \
      '#!/bin/sh' \
      ': >"${TOOL_ARGS:?}"' \
      'for arg do printf "<%s>\\n" "$arg" >>"${TOOL_ARGS}"; done' \
      'printf payload' >"${mock_bin}/mydumper" || return 1
    printf '%s\n' \
      '#!/bin/sh' \
      ': >"${TOOL_ARGS:?}"' \
      'for arg do printf "<%s>\\n" "$arg" >>"${TOOL_ARGS}"; done' \
      'cat >/dev/null' >"${mock_bin}/myloader" || return 1
    printf '%s\n' \
      '#!/bin/sh' \
      'case "$1" in' \
      '  push) cat >/dev/null ;;' \
      '  pull) printf payload ;;' \
      '  stat) printf "TotalSize 7\\n" ;;' \
      'esac' >"${mock_bin}/datasafed" || return 1
    chmod +x "${mock_bin}/mydumper" "${mock_bin}/myloader" "${mock_bin}/datasafed"
  }

  argument_after() {
    option=$1
    args_file=$2
    awk -v option="<${option}>" '
      $0 == option { getline; print; found = 1; exit }
      END { if (!found) exit 1 }
    ' "${args_file}"
  }

  verify_mydumper_preserves_filter_arguments() {
    root=$(mktemp -d "${TMPDIR:-/tmp}/mysql-mydumper-argv.XXXXXX") || return 1
    write_mock_tools "${root}/bin" || return 1
    touch "${root}/db.table_one" "${root}/db.table_two"

    (
      cd "${root}" || exit 1
      export PATH="${root}/bin:${PATH}"
      export TOOL_ARGS="${root}/mydumper.args"
      export DP_DATASAFED_BIN_PATH="${root}/bin"
      export DP_BACKUP_BASE_PATH="/repo/current"
      export DP_BACKUP_NAME="current"
      export DP_BACKUP_INFO_FILE="${root}/progress"
      export DP_DB_HOST="mysql"
      export DP_DB_PORT="3306"
      export DP_DB_USER="backup"
      export DP_DB_PASSWORD="secret"
      export threads="4"
      export tables="db.table*"
      export trx_tables="false"
      export no_data="false"
      export databases="sales archive"
      bash "$(chart_path)/dataprotection/mysql-mydumper.sh" >/dev/null 2>&1
    ) || return 1

    [ "$(argument_after -T "${root}/mydumper.args")" = '<db.table*>' ] &&
      [ "$(argument_after -B "${root}/mydumper.args")" = '<sales archive>' ]
    status=$?
    rm -rf "${root}"
    return "${status}"
  }

  verify_myloader_preserves_filter_arguments() {
    root=$(mktemp -d "${TMPDIR:-/tmp}/mysql-myloader-argv.XXXXXX") || return 1
    write_mock_tools "${root}/bin" || return 1
    touch "${root}/db.table_one" "${root}/db.table_two"

    (
      cd "${root}" || exit 1
      export PATH="${root}/bin:${PATH}"
      export TOOL_ARGS="${root}/myloader.args"
      export DP_DATASAFED_BIN_PATH="${root}/bin"
      export DP_BACKUP_BASE_PATH="/repo/current"
      export DP_BACKUP_NAME="current"
      export DP_BACKUP_INFO_FILE="${root}/progress"
      export DP_DB_HOST="mysql"
      export DP_DB_PORT="3306"
      export MYSQL_ADMIN_USER="root"
      export MYSQL_ADMIN_PASSWORD="secret"
      export threads="4"
      export tables="db.table*"
      export drop_table="FAIL"
      export no_data="false"
      bash "$(chart_path)/dataprotection/mysql-myloader.sh" >/dev/null 2>&1
    ) || return 1

    [ "$(argument_after -T "${root}/myloader.args")" = '<db.table*>' ]
    status=$?
    rm -rf "${root}"
    return "${status}"
  }

  It "passes each mydumper database and table filter as one literal argument"
    When call verify_mydumper_preserves_filter_arguments
    The status should be success
  End

  It "passes each myloader table filter as one literal argument"
    When call verify_myloader_preserves_filter_arguments
    The status should be success
  End
End
