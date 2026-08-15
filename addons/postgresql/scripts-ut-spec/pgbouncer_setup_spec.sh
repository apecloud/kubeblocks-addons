# shellcheck shell=bash
# shellcheck disable=SC2034,SC2317,SC2329

Describe "PostgreSQL Pgbouncer setup fail-fast contract"
  Include ../scripts/pgbouncer-setup.sh

  setup() {
    test_dir=$(mktemp -d -t pgbouncer-failfast-XXXXXX)
    pgbouncer_template_conf_file="../config/pgbouncer-ini.tpl"
    pgbouncer_conf_dir="$test_dir/conf/"
    pgbouncer_log_dir="$test_dir/logs/"
    pgbouncer_tmp_dir="$test_dir/tmp/"
    pgbouncer_conf_file="$test_dir/conf/pgbouncer.ini"
    pgbouncer_user_list_file="$test_dir/conf/userlist.txt"
    POSTGRESQL_USERNAME=postgres
    POSTGRESQL_PASSWORD=secret
    CURRENT_POD_IP=127.0.0.1
    export PGB_FAIL_STEP=chown
  }

  cleanup() {
    rm -rf "$test_dir"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  is_empty() {
    test -z "${1:-}"
  }

  Mock useradd
    exit 0
  End

  Mock load_common_library
    exit 0
  End

  Mock id
    if test "${1:-}" = "-g"; then
      printf '%s\n' 1001
    fi
    exit 0
  End

  Mock getent
    exit 0
  End

  Mock cp
    if test "$PGB_FAIL_STEP" = "cp"; then
      exit 42
    fi
    /bin/cp "$@"
  End

  Mock chown
    if test "$PGB_FAIL_STEP" = "chown"; then
      exit 42
    fi
    exit 0
  End

  Mock start_pgbouncer
    printf '%s\n' start-called
    exit 0
  End

  It "does not start Pgbouncer after ownership setup fails"
    When call main
    The status should be failure
    The output should not include "start-called"
  End

  It "does not start Pgbouncer after copying the template fails"
    export PGB_FAIL_STEP=cp
    When call main
    The status should be failure
    The output should not include "start-called"
  End
End
