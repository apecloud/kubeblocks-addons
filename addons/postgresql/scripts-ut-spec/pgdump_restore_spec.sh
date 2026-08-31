# shellcheck shell=sh

Describe "dataprotection/pgdump-restore.sh owner and privilege contract"

  script_path() {
    printf "%s" "../dataprotection/pgdump-restore.sh"
  }

  actionset_path() {
    printf "%s" "../templates/actionset-pgdump.yaml"
  }

  setup() {
    tmpdir=$(mktemp -d -t pg-dump-restore-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"
    DP_DATASAFED_BIN_PATH="${bindir}"
    DP_BACKUP_BASE_PATH="/backup"
    DP_BACKUP_NAME="backup-test"
    POSTGRES_PASSWORD="secret"
    POSTGRES_USER="postgres"
    DP_DB_HOST="localhost"
    DP_DB_PORT="5432"
    BACKUP_DIR="${tmpdir}/restore-workdir"
    export PATH CALL_LOG DP_DATASAFED_BIN_PATH DP_BACKUP_BASE_PATH \
      DP_BACKUP_NAME POSTGRES_PASSWORD POSTGRES_USER DP_DB_HOST DP_DB_PORT BACKUP_DIR
    unset PG_RESTORE_EXIT PG_RESTORE_STDERR jobs database schemas tables \
      schema_only conflict_policy skip_owner skip_privileges 2>/dev/null || true
    write_stubs
  }

  cleanup() {
    rm -rf "${tmpdir}"
    rm -f /tmp/pg_restore.log
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  write_stubs() {
    cat > "${bindir}/datasafed" <<'EOF'
#!/bin/sh
printf 'datasafed %s\n' "$*" >> "${CALL_LOG}"
printf '%s\n' '-- dump data'
EOF
    cat > "${bindir}/tar" <<'EOF'
#!/bin/sh
printf 'tar %s\n' "$*" >> "${CALL_LOG}"
cat > /dev/null
EOF
    cat > "${bindir}/psql" <<'EOF'
#!/bin/sh
printf 'psql %s\n' "$*" >> "${CALL_LOG}"
exit 0
EOF
    cat > "${bindir}/pg_restore" <<'EOF'
#!/bin/sh
printf 'pg_restore %s\n' "$*" >> "${CALL_LOG}"
if [ -n "${PG_RESTORE_STDERR:-}" ]; then
  printf '%s\n' "${PG_RESTORE_STDERR}" >&2
fi
exit "${PG_RESTORE_EXIT:-0}"
EOF
    chmod +x "${bindir}/datasafed" "${bindir}/tar" "${bindir}/psql" "${bindir}/pg_restore"
  }

  call_log() {
    cat "${CALL_LOG}"
  }

  restore_parameters() {
    grep '^pg_restore ' "${CALL_LOG}"
  }

  actionset_schema() {
    cat "$(actionset_path)"
  }

  restore_parameter_names() {
    awk '/^  restore:/{restore=1} restore && /^    withParameters:/{params=1; next} params && /^    [a-zA-Z]/{exit} params{print}' "$(actionset_path)"
  }

  It "restores archive owners and privileges by default"
    When run bash "$(script_path)"
    The status should eq 0
    The result of function restore_parameters should not include "--no-owner"
    The result of function restore_parameters should not include "--no-privileges"
  End

  It "skips only owners when skip_owner is true"
    export skip_owner="true"
    When run bash "$(script_path)"
    The status should eq 0
    The result of function restore_parameters should include "--no-owner"
    The result of function restore_parameters should not include "--no-privileges"
  End

  It "skips only privileges when skip_privileges is true"
    export skip_privileges="true"
    When run bash "$(script_path)"
    The status should eq 0
    The result of function restore_parameters should not include "--no-owner"
    The result of function restore_parameters should include "--no-privileges"
  End

  It "supports explicitly skipping owners and privileges together"
    export skip_owner="true"
    export skip_privileges="true"
    When run bash "$(script_path)"
    The status should eq 0
    The result of function restore_parameters should include "--no-owner"
    The result of function restore_parameters should include "--no-privileges"
  End

  It "does not downgrade a missing archive role to success"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR='pg_restore: error: could not execute query: ERROR: role "app" does not exist
pg_restore: warning: errors ignored on restore: 1'
    When run bash "$(script_path)"
    The status should be failure
    The output should include "parameters:"
    The error should include 'role "app" does not exist'
    The error should include "pg_restore reported non-conflict errors; failing restore"
  End

  It "declares and passes the two opt-out parameters"
    When call actionset_schema
    The output should include "skip_owner:"
    The output should include "skip_privileges:"
    The output should include 'description: "Skip restoring object owners.'
    The output should include 'description: "Skip restoring object privileges.'
    The result of function restore_parameter_names should include "- skip_owner"
    The result of function restore_parameter_names should include "- skip_privileges"
  End
End
