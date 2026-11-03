# shellcheck shell=bash
# shellcheck disable=SC2034,SC2317,SC2329

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "postgres_pre_setup_spec.sh requires bash 4 or higher."
  exit 0
fi

Describe "PostgreSQL initialization"
  Include ../scripts/postgres-pre-setup.sh

  setup() {
    tmpdir=$(mktemp -d -t pg-pre-setup-XXXXXX)
    setup_script=$(cd ../scripts && pwd)/postgres-pre-setup.sh
    postgres_template_conf_file="${tmpdir}/template config.conf"
    postgres_conf_dir="${tmpdir}/config dir"
    postgres_conf_file="${postgres_conf_dir}/template config.conf"
    printf '%s\n' "listen_addresses = '*'" "port = '5432'" > "${postgres_template_conf_file}"
    bindir="${tmpdir}/bin"
    command mkdir -p "${bindir}"
    PRESETUP_CALL_LOG="${tmpdir}/calls.log"
    : > "${PRESETUP_CALL_LOG}"

    # Stub filesystem commands only in the standalone process. No writes are
    # made to the production script's /home/postgres or /spilo-init paths.
    cat > "${bindir}/setup-command" <<'EOF'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >> "${PRESETUP_CALL_LOG}"
count=$(wc -l < "${PRESETUP_CALL_LOG}")
if [ "${count}" -eq "${PRESETUP_FAIL_AT:-0}" ]; then
  exit 42
fi
exit 0
EOF
    command chmod +x "${bindir}/setup-command"
    for cmd in mkdir cp chmod touch; do
      ln -s setup-command "${bindir}/${cmd}"
    done
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }
  BeforeEach 'setup'
  AfterEach 'cleanup'

  run_standalone() {
    # Start with a fresh Bash process rather than calling helpers in the
    # ShellSpec runner, whose conditional calls can suppress errexit.
    env -u __SOURCED__ -u BASH_ENV -u SHELLOPTS \
      PATH="${bindir}:${PATH}" PRESETUP_CALL_LOG="${PRESETUP_CALL_LOG}" \
      PRESETUP_FAIL_AT="${1:-0}" "${SHELLSPEC_SHELL}" "${setup_script}"
  }

  source_without_initializing() {
    env -u BASH_ENV -u SHELLOPTS __SOURCED__=1 \
      PATH="${bindir}:${PATH}" PRESETUP_CALL_LOG="${PRESETUP_CALL_LOG}" \
      "${SHELLSPEC_SHELL}" -c '
        . "$1"
        case $- in *e*) exit 91 ;; esac
        declare -F main >/dev/null
      ' -- "${setup_script}"
  }

  command_count() {
    wc -l < "${PRESETUP_CALL_LOG}" | tr -d '[:space:]'
  }

  last_command() {
    tail -n 1 "${PRESETUP_CALL_LOG}"
  }

  It "copies the configuration with quoted paths containing spaces"
    When call build_real_postgres_conf
    The status should be success
    The path "${postgres_conf_dir}" should be directory
    The contents of file "${postgres_conf_file}" should include "listen_addresses = '*'"
    The contents of file "${postgres_conf_file}" should include "port = '5432'"
  End

  It "can be sourced without enabling errexit or running initialization"
    When call source_without_initializing
    The status should be success
    The result of function command_count should eq 0
  End

  It "completes all setup steps when the standalone commands succeed"
    When call run_standalone
    The status should be success
    The result of function command_count should eq 10
    The result of function last_command should eq "cp /spilo-init/bin/wal-g /home/postgres/pgdata/wal-g/wal-g"
  End

  Describe "standalone failure handling"
    Parameters
      1 'mkdir -p /home/postgres/pgdata/conf/'
      2 'cp /home/postgres/conf/postgresql.conf /home/postgres/pgdata/conf/'
      3 'chmod 755 /home/postgres/pgdata/conf/'
      4 'chmod 664 /home/postgres/pgdata/conf/postgresql.conf'
      5 'mkdir -p /home/postgres/pgdata/logs/'
      6 'chmod -R 777 /home/postgres/pgdata/logs/'
      7 'touch /home/postgres/pgdata/logs//scripts.log'
      8 'chmod 666 /home/postgres/pgdata/logs//scripts.log'
      9 'mkdir -p /home/postgres/pgdata/wal-g'
      10 'cp /spilo-init/bin/wal-g /home/postgres/pgdata/wal-g/wal-g'
    End

    It "stops at failed setup command $1: $2"
      When call run_standalone "$1"
      The status should eq 42
      The result of function command_count should eq "$1"
      The result of function last_command should eq "$2"
    End
  End
End
