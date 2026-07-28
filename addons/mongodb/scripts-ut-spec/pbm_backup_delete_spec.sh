# shellcheck shell=bash

Describe "MongoDB PBM backup delete contract"
  setup_pbm_backup_delete() {
    test_root=$(mktemp -d "${TMPDIR:-/tmp}/mongodb-pbm-delete-spec.XXXXXX")
    fake_bin="$test_root/bin"
    original_path=$PATH
    mkdir -p "$fake_bin"

    cat >"$fake_bin/datasafed" <<'SH'
#!/bin/sh
command_name=${1:-}
printf '%s|%s' "$DATASAFED_BACKEND_BASE_PATH" "${1:-}" >>"$MONGODB_TEST_CALL_LOG"
shift
for arg in "$@"; do
  printf '|%s' "$arg" >>"$MONGODB_TEST_CALL_LOG"
done
printf '\n' >>"$MONGODB_TEST_CALL_LOG"

case "$command_name" in
  list)
    if [ -n "${MONGODB_TEST_LIST_RC:-}" ]; then
      exit "$MONGODB_TEST_LIST_RC"
    fi
    target=${1:-}
    case "$target" in
      kubeblocks-backup.json)
        if [ "${MONGODB_TEST_METADATA_PRESENT:-1}" = "1" ]; then
          printf 'kubeblocks-backup.json\n'
        fi
        ;;
      /)
        printf 'artifact-one\nartifact-two\n'
        ;;
      *)
        printf '%s\n' "$target"
        ;;
    esac
    ;;
  pull)
    if [ -n "${MONGODB_TEST_PULL_OUTPUT:-}" ]; then
      printf '%s\n' "$MONGODB_TEST_PULL_OUTPUT"
    fi
    exit "${MONGODB_TEST_PULL_RC:-0}"
    ;;
  rm)
    exit "${MONGODB_TEST_RM_RC:-0}"
    ;;
  *)
    exit 64
    ;;
esac
SH
    chmod +x "$fake_bin/datasafed"

    export PATH="$fake_bin:$original_path"
    export DP_DATASAFED_BIN_PATH="$fake_bin"
    export DP_BACKUP_BASE_PATH="/repo/backups/job-1"
    export PBM_BACKUP_TYPE="physical"
    export PBM_BACKUP_DIR_NAME="pbm"
    export RETAIN_PITR_FILES="false"
    export MONGODB_TEST_CALL_LOG="$test_root/calls.log"
    export MONGODB_TEST_METADATA_PRESENT=1
    export MONGODB_TEST_PULL_OUTPUT='{"status":"Completed","extras":[{"backup_name":"backup-2026"}]}'
    unset MONGODB_TEST_LIST_RC MONGODB_TEST_PULL_RC MONGODB_TEST_RM_RC
    : >"$MONGODB_TEST_CALL_LOG"
  }
  Before "setup_pbm_backup_delete"

  cleanup_pbm_backup_delete() {
    PATH=$original_path
    export PATH
    rm -rf "$test_root"
    unset test_root fake_bin original_path
    unset DP_DATASAFED_BIN_PATH DP_BACKUP_BASE_PATH
    unset PBM_BACKUP_TYPE PBM_BACKUP_DIR_NAME RETAIN_PITR_FILES
    unset MONGODB_TEST_CALL_LOG MONGODB_TEST_METADATA_PRESENT
    unset MONGODB_TEST_PULL_OUTPUT MONGODB_TEST_LIST_RC
    unset MONGODB_TEST_PULL_RC MONGODB_TEST_RM_RC
  }
  After "cleanup_pbm_backup_delete"

  run_delete_and_report() {
    local status

    "$SHELLSPEC_SHELL" ../dataprotection/pbm-backup-delete.sh
    status=$?
    printf '%s\n' "--- calls ---"
    cat "$MONGODB_TEST_CALL_LOG"
    return "$status"
  }

  It "deletes PBM artifacts named by valid completed backup metadata"
    When call run_delete_and_report

    The status should be success
    The output should include "INFO: Backup status: Completed"
    The output should include "INFO: Backup name: backup-2026"
    The output should include "repo/backups/pbm|rm|backup-2026|-r"
    The output should include "repo/backups/pbm|rm|backup-2026.pbm.json"
    The output should include "INFO: PBM backup delete script completed successfully."
    The stderr should be blank
  End

  It "keeps deletion idempotent when metadata is already absent"
    export MONGODB_TEST_METADATA_PRESENT=0

    When call run_delete_and_report

    The status should be success
    The output should include "INFO: Backup has been deleted."
    The output should not include "|rm|"
    The stderr should be blank
  End

  It "skips PBM artifact deletion when metadata has no backup name"
    export MONGODB_TEST_PULL_OUTPUT='{"status":"Running","extras":[{}]}'

    When call run_delete_and_report

    The status should be success
    The output should include "INFO: Backup status: Running"
    The output should include "INFO: Backup name:"
    The output should include "skip handling."
    The output should not include "|rm|"
    The stderr should be blank
  End

  It "fails closed on malformed backup metadata without deleting artifacts"
    export MONGODB_TEST_PULL_OUTPUT='{invalid-json'

    When call run_delete_and_report

    The status should be failure
    The output should not include "|rm|"
    The stderr should include "parse error"
  End

  It "preserves metadata probe failure without reporting an idempotent delete"
    export MONGODB_TEST_LIST_RC=17

    When call run_delete_and_report

    The status should equal 17
    The output should not include "INFO: Backup has been deleted."
    The output should not include "|rm|"
    The stderr should be blank
  End

  It "rejects multiple backup metadata documents before deleting artifacts"
    export MONGODB_TEST_PULL_OUTPUT='{"status":"Completed","extras":[{"backup_name":"one"}]}
{"status":"Completed","extras":[{"backup_name":"two"}]}'

    When call run_delete_and_report

    The status should be failure
    The output should not include "|rm|"
    The stderr should not be blank
  End

  It "rejects a non-string backup name before deleting artifacts"
    export MONGODB_TEST_PULL_OUTPUT='{"status":"Completed","extras":[{"backup_name":42}]}'

    When call run_delete_and_report

    The status should be failure
    The output should not include "|rm|"
    The stderr should not be blank
  End

  It "rejects an unsafe backup path before deleting artifacts"
    export MONGODB_TEST_PULL_OUTPUT='{"status":"Completed","extras":[{"backup_name":"../other-backup"}]}'

    When call run_delete_and_report

    The status should be failure
    The output should not include "|rm|"
    The stderr should not be blank
  End
End
