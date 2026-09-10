# shellcheck shell=bash
# shellcheck disable=SC2034,SC2317,SC2329

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "postgres_pre_setup_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "PostgreSQL Configuration Script Tests"

  Include ../scripts/postgres-pre-setup.sh

  mkdir() {
    if test "${PRESETUP_FAIL_STEP:-}" = "mkdir"; then
      return 42
    fi
    command mkdir "$@"
  }

  cp() {
    if test "${PRESETUP_FAIL_STEP:-}" = "cp"; then
      return 42
    fi
    if test "${PRESETUP_STUB_CP_SUCCESS:-0}" = "1"; then
      return 0
    fi
    command cp "$@"
  }

  touch() {
    if test "${PRESETUP_FAIL_STEP:-}" = "touch"; then
      return 42
    fi
    command touch "$@"
  }

  init() {
    postgres_template_conf_file="./postgresql.conf"
    postgres_conf_dir="./pgdata/"
    postgres_conf_file="./pgdata/postgresql.conf"
    postgres_log_dir="./pgdata/logs/"
    postgres_scripts_log_file="${postgres_log_dir}/scripts.log"
    postgres_walg_dir="./pgdata/wal-g"
    touch "$postgres_template_conf_file"
    mkdir -p "$postgres_log_dir" "$postgres_walg_dir"
    touch "$postgres_conf_file" "$postgres_scripts_log_file"
    echo "listen_addresses = '*'
          port = '5432'
          archive_command = '/bin/true'
          archive_mode = 'on'
          auto_explain.log_analyze = 'False'
          auto_explain.log_buffers = 'False'" > "$postgres_template_conf_file"
  }
  BeforeAll "init"

  cleanup() {
    rm -rf "$postgres_template_conf_file" "$postgres_conf_dir" "$postgres_conf_file"
  }
  AfterAll 'cleanup'

  Describe "build_real_postgres_conf()"
    It "builds the PostgreSQL configuration file"
      When call build_real_postgres_conf
      The status should be success
      The path "$postgres_conf_dir" should be directory
      The path "$postgres_conf_file" should be file
      The contents of file "$postgres_conf_file" should include "listen_addresses = '*'"
      The contents of file "$postgres_conf_file" should include "port = '5432'"
      The contents of file "$postgres_conf_file" should include "archive_command = '/bin/true'"
    End
  End

  Describe "build_real_postgres_conf() failure"
    It "preserves a template copy failure"
      export PRESETUP_FAIL_STEP=cp
      When call build_real_postgres_conf
      The status should equal 42
    End
  End

  Describe "init_postgres_log() failure"
    It "preserves a log-file creation failure"
      export PRESETUP_FAIL_STEP=touch
      When call init_postgres_log
      The status should equal 42
    End
  End

  Describe "copy_necessary_binaries() failure"
    It "preserves a WAL-G directory creation failure"
      export PRESETUP_FAIL_STEP=mkdir
      export PRESETUP_STUB_CP_SUCCESS=1
      When call copy_necessary_binaries
      The status should equal 42
    End
  End

  Describe "main()"
    Mock build_real_postgres_conf
      exit 42
    End

    Mock init_postgres_log
      echo init-called
      exit 0
    End

    Mock copy_necessary_binaries
      echo copy-called
      exit 0
    End

    It "stops after configuration setup fails"
      When call main
      The status should equal 42
      The output should not include "init-called"
      The output should not include "copy-called"
    End
  End
End
