# shellcheck shell=sh

Describe "dataprotection/pgdump-restore.sh"

  script_path() {
    printf "%s" "../dataprotection/pgdump-restore.sh"
  }

  setup() {
    tmpdir=$(mktemp -d -t pg-dump-restore-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"
    rm -f /tmp/pg_restore.log
    DP_DATASAFED_BIN_PATH="${bindir}"
    DP_BACKUP_BASE_PATH="/backup"
    DP_BACKUP_NAME="backup-test"
    DP_DB_PASSWORD="dp-secret"
    DP_DB_USER="kbdataprotection"
    DP_DB_HOST="localhost"
    DP_DB_PORT="5432"
    BACKUP_DIR="${tmpdir}/restore-workdir"
    export PATH CALL_LOG DP_DATASAFED_BIN_PATH DP_BACKUP_BASE_PATH \
      DP_BACKUP_NAME DP_DB_PASSWORD DP_DB_USER DP_DB_HOST DP_DB_PORT BACKUP_DIR
    unset DATASAFED_LIST_OUT DATASAFED_PULL_EXIT PG_RESTORE_EXIT PG_RESTORE_STDERR \
      jobs database schemas tables schema_only conflict_policy skip_owner skip_privileges 2>/dev/null || true
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
cmd="$1"
case "$cmd" in
  list) printf '%s\n' "${DATASAFED_LIST_OUT:-}" ;;
  pull)
    if [ "${DATASAFED_PULL_EXIT:-0}" -ne 0 ]; then
      exit "${DATASAFED_PULL_EXIT}"
    fi
    printf '%s\n' "-- dump data"
    ;;
esac
EOF
    cat > "${bindir}/tar" <<'EOF'
#!/bin/sh
printf 'tar %s\n' "$*" >> "${CALL_LOG}"
cat > /dev/null
EOF
    cat > "${bindir}/psql" <<'EOF'
#!/bin/sh
printf 'psql PGPASSWORD=%s args=%s\n' "${PGPASSWORD}" "$*" >> "${CALL_LOG}"
exit 0
EOF
    cat > "${bindir}/pg_restore" <<'EOF'
#!/bin/sh
printf 'pg_restore PGPASSWORD=%s args=%s\n' "${PGPASSWORD}" "$*" >> "${CALL_LOG}"
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

  It "fails loudly when the backup file does not exist in the repository"
    export DATASAFED_LIST_OUT=""
    When run bash "$(script_path)"
    The status should be failure
    The error should include "backup-test.tar not found"
    The result of function call_log should not include "pg_restore"
  End

  It "uses the DataProtection user and password for psql and pg_restore"
    export DATASAFED_LIST_OUT="backup-test.tar"
    export database="application"
    When run bash "$(script_path)"
    The status should eq 0
    The result of function call_log should include "psql PGPASSWORD=dp-secret args=-h localhost -U kbdataprotection -p 5432"
    The result of function call_log should include "pg_restore PGPASSWORD=dp-secret args=-h localhost -U kbdataprotection -p 5432"
  End

  It "restores successfully when the backup exists and pg_restore succeeds"
    export DATASAFED_LIST_OUT="backup-test.tar"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "parameters:"
    The result of function call_log should include "pg_restore"
  End

  It "fails when the ignored-errors warning has no error details"
    export DATASAFED_LIST_OUT="backup-test.tar"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR="pg_restore: warning: errors ignored on restore: 3"
    When run bash "$(script_path)"
    The status should be failure
    The output should include "parameters:"
    The error should include "errors ignored on restore"
  End

  It "treats existing-object errors as success under the default CONTINUE policy"
    export DATASAFED_LIST_OUT="backup-test.tar"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR='pg_restore: error: could not execute query: ERROR: relation "items" already exists
pg_restore: warning: errors ignored on restore: 1'
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "treating as success under conflict_policy=CONTINUE"
    The error should include "already exists"
  End

  It "propagates ignored-error failures when conflict_policy is FAIL"
    export DATASAFED_LIST_OUT="backup-test.tar"
    export conflict_policy="FAIL"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR="pg_restore: warning: errors ignored on restore: 3"
    When run bash "$(script_path)"
    The status should be failure
    The output should include "--exit-on-error"
    The error should include "errors ignored on restore"
  End

  It "fails when pg_restore fails without the ignored-errors warning"
    export DATASAFED_LIST_OUT="backup-test.tar"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR="pg_restore: error: could not connect to server"
    When run bash "$(script_path)"
    The status should be failure
    The output should include "parameters:"
    The error should include "could not connect"
  End

  It "fails when datasafed pull fails mid-stream"
    export DATASAFED_LIST_OUT="backup-test.tar"
    export DATASAFED_PULL_EXIT=1
    When run bash "$(script_path)"
    The status should be failure
    The result of function call_log should not include "pg_restore"
  End
  actionset_path() { printf "%s" "../templates/actionset-pgdump.yaml"; }

  restore_parameters() {
    grep '^pg_restore ' "${CALL_LOG}"
  }

  actionset_schema() {
    cat "$(actionset_path)"
  }

  restore_parameter_names() {
    awk '/^  restore:/{restore=1} restore && /^    withParameters:/{params=1; next} params && /^    [a-zA-Z]/{exit} params{print}' "$(actionset_path)"
  }

  restore_parameter_contract() {
    awk -v parameter="$1" '
      $0 == "        " parameter ":" { found=1; next }
      found && /^        [a-zA-Z0-9_]+:$/ { exit }
      found && /^          type:/ {
        sub(/^          type:[[:space:]]*/, "type=")
        print
      }
      found && /^          default:/ {
        sub(/^          default:[[:space:]]*/, "default=")
        print
      }
    ' "$(actionset_path)"
  }

  skip_owner_contract() {
    restore_parameter_contract skip_owner
  }

  skip_privileges_contract() {
    restore_parameter_contract skip_privileges
  }

  It "restores archive owners and privileges by default"
    export DATASAFED_LIST_OUT="backup-test.tar"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "parameters:"
    The result of function restore_parameters should not include "--no-owner"
    The result of function restore_parameters should not include "--no-privileges"
  End

  It "skips only owners when skip_owner is true"
    export skip_owner="true"
    export DATASAFED_LIST_OUT="backup-test.tar"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "parameters:"
    The result of function restore_parameters should include "--no-owner"
    The result of function restore_parameters should not include "--no-privileges"
  End

  It "skips only privileges when skip_privileges is true"
    export skip_privileges="true"
    export DATASAFED_LIST_OUT="backup-test.tar"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "parameters:"
    The result of function restore_parameters should not include "--no-owner"
    The result of function restore_parameters should include "--no-privileges"
  End

  It "supports explicitly skipping owners and privileges together"
    export skip_owner="true"
    export skip_privileges="true"
    export DATASAFED_LIST_OUT="backup-test.tar"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "parameters:"
    The result of function restore_parameters should include "--no-owner"
    The result of function restore_parameters should include "--no-privileges"
  End

  It "does not downgrade a missing archive role to success"
    export PG_RESTORE_EXIT=1
    export PG_RESTORE_STDERR='pg_restore: error: could not execute query: ERROR: role "app" does not exist
pg_restore: warning: errors ignored on restore: 1'
    export DATASAFED_LIST_OUT="backup-test.tar"
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
    The result of function skip_owner_contract should include "type=boolean"
    The result of function skip_owner_contract should include "default=false"
    The result of function skip_privileges_contract should include "type=boolean"
    The result of function skip_privileges_contract should include "default=false"
  End
End
