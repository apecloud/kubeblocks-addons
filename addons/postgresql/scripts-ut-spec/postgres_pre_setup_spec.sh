# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "postgres_pre_setup_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "PostgreSQL Configuration Script Tests"

  Include ../scripts/postgres-pre-setup.sh

  init() {
    postgres_template_conf_file="./postgresql.conf"
    postgres_conf_dir="./pgdata/"
    postgres_conf_file="./pgdata/postgresql.conf"
    touch $postgres_template_conf_file
    echo "listen_addresses = '*'
          port = '5432'
          archive_command = '/bin/true'
          archive_mode = 'on'
          auto_explain.log_analyze = 'False'
          auto_explain.log_buffers = 'False'" > $postgres_template_conf_file
  }
  BeforeAll "init"

  cleanup() {
    rm -rf $postgres_template_conf_file $postgres_conf_dir $postgres_conf_file
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
End