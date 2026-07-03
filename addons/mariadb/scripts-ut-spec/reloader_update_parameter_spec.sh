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
