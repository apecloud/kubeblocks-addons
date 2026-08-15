# shellcheck shell=bash

Describe "dataprotection/backup-info-collector.sh"
  setup() {
    tmpdir=$(mktemp -d -t pg-backup-info-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"
    DP_DB_USER="kbdataprotection"
    DP_DB_HOST="postgres.example.test"
    DP_DB_PORT="6432"
    export PATH CALL_LOG DP_DB_USER DP_DB_HOST DP_DB_PORT
    write_stubs
    . ../dataprotection/backup-info-collector.sh
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  write_stubs() {
    cat > "${bindir}/psql" <<'EOF'
#!/bin/sh
printf 'psql %s\n' "$*" >> "${CALL_LOG}"
printf '%s\n' '2026-08-15 15:00:00'
EOF
    chmod +x "${bindir}/psql"
  }

  call_log() {
    cat "${CALL_LOG}"
  }

  It "queries time through the ActionSet-injected database port"
    When call get_current_time
    The status should eq 0
    The output should eq "2026-08-15 15:00:00"
    The result of function call_log should include "psql -U kbdataprotection -h postgres.example.test -p 6432 -d postgres"
  End
End
