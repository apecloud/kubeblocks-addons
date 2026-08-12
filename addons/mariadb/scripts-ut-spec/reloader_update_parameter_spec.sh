# shellcheck shell=sh

Describe "reloader/update-parameter.sh"

  repo_root() {
    printf "%s" "${SHELLSPEC_CWD:?}"
  }

  script_path() {
    printf "%s/addons/mariadb/reloader/update-parameter.sh" "$(repo_root)"
  }

  setup() {
    tmpdir=$(mktemp -d -t mariadb-reloader-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    MARIADB_ROOT_USER="root"
    MARIADB_ROOT_PASSWORD="secret"
    unset MARIADB_INTERNAL_ROOT_USER
    export PATH MARIADB_ROOT_USER MARIADB_ROOT_PASSWORD
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  write_mariadb_stub() {
    rc="$1"
    stderr="$2"
    cat > "${bindir}/mariadb" <<EOF
#!/bin/sh
printf '%s\n' "$stderr" >&2
exit "$rc"
EOF
    chmod +x "${bindir}/mariadb"
  }

  write_recording_mariadb_stub() {
    cat > "${bindir}/mariadb" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "${MARIADB_TEST_ARGS_FILE}"
EOF
    chmod +x "${bindir}/mariadb"
  }

  Describe "administrative account"
    It "uses kb_internal_root by default instead of user-facing root"
      MARIADB_TEST_ARGS_FILE="${tmpdir}/args"
      export MARIADB_TEST_ARGS_FILE
      write_recording_mariadb_stub

      When run bash "$(script_path)" "slave_parallel_threads" "4"
      The status should eq 0
      The contents of file "${MARIADB_TEST_ARGS_FILE}" should include "--user=kb_internal_root"
      The contents of file "${MARIADB_TEST_ARGS_FILE}" should not include "--user=root"
      The contents of file "${MARIADB_TEST_ARGS_FILE}" should include 'SET GLOBAL `slave_parallel_threads` = 4;'
    End

    It "honors an explicitly configured internal administrative account"
      MARIADB_INTERNAL_ROOT_USER="custom_internal_root"
      MARIADB_TEST_ARGS_FILE="${tmpdir}/args"
      export MARIADB_INTERNAL_ROOT_USER MARIADB_TEST_ARGS_FILE
      write_recording_mariadb_stub

      When run bash "$(script_path)" "slave_parallel_threads" "4"
      The status should eq 0
      The contents of file "${MARIADB_TEST_ARGS_FILE}" should include "--user=custom_internal_root"
      The contents of file "${MARIADB_TEST_ARGS_FILE}" should not include "--user=root"
    End
  End

  Describe "classified user-input SQL errors"
    It "skips ERROR 1232 without returning failure"
      write_mariadb_stub 1 "ERROR 1232 (42000) at line 1: Incorrect argument type to variable 'log_warnings'"

      When run bash "$(script_path)" "log_warnings" "nonsense"
      The status should eq 0
      The output should include "[REJECT] parameter log_warnings=nonsense rejected by engine (error 1232)"
      The error should include "[REJECT] parameter log_warnings=nonsense rejected by engine (error 1232)"
      The error should not include "Failed to set parameter"
    End

    It "skips ERROR 1231 without returning failure"
      write_mariadb_stub 1 "ERROR 1231 (42000) at line 1: Variable 'long_query_time' can't be set to the value of 'bad'"

      When run bash "$(script_path)" "long_query_time" "bad"
      The status should eq 0
      The output should include "[REJECT] parameter long_query_time=bad rejected by engine (error 1231)"
      The error should not include "Failed to set parameter"
    End
  End

  Describe "unclassified SQL errors"
    It "still fails closed"
      write_mariadb_stub 1 "ERROR 1045 (28000): Access denied for user"

      When run bash "$(script_path)" "long_query_time" "7"
      The status should eq 1
      The error should include "Failed to set parameter long_query_time to value 7"
    End
  End
End
