# shellcheck shell=sh

Describe "PostgreSQL WAL-G preDelete failure propagation"

  setup() {
    tmpdir=$(mktemp -d -t pg-walg-delete-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"
    DP_DATASAFED_BIN_PATH="${bindir}"
    DP_BACKUP_BASE_PATH="/repo/backup-test"
    DP_BACKUP_NAME="backup-test"
    dataprotection_dir=$(cd ../dataprotection && pwd)
    export PATH CALL_LOG DP_DATASAFED_BIN_PATH DP_BACKUP_BASE_PATH \
      DP_BACKUP_NAME
    unset DATASAFED_LIST_EXIT WALG_TARGET_EXIT WALG_ARCHIVE_EXIT 2>/dev/null || true
    write_stubs
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  write_stubs() {
    cat > "${bindir}/datasafed" <<'EOF'
#!/bin/sh
printf 'datasafed %s\n' "$*" >> "${CALL_LOG}"
if [ "$1" = "list" ]; then
  if [ "${DATASAFED_LIST_EXIT:-0}" -ne 0 ]; then
    exit "${DATASAFED_LIST_EXIT}"
  fi
  case "$*" in
    "list wal-g-backup-repo.path") printf '%s\n' wal-g-backup-repo.path ;;
    "list wal-g-backup-name") printf '%s\n' wal-g-backup-name ;;
    *"/basebackups_005"*) printf '%s\n' base_00000001 ;;
  esac
elif [ "$1" = "pull" ]; then
  case "$2" in
    wal-g-backup-repo.path) printf '%s\n' /repo/wal-g > "$3" ;;
    wal-g-backup-name) printf '%s\n' base_00000001 > "$3" ;;
  esac
fi
exit 0
EOF
    cat > "${bindir}/wal-g" <<'EOF'
#!/bin/sh
printf 'wal-g %s\n' "$*" >> "${CALL_LOG}"
case "$*" in
  "delete target "*) exit "${WALG_TARGET_EXIT:-0}" ;;
  "delete garbage ARCHIVES --confirm") exit "${WALG_ARCHIVE_EXIT:-0}" ;;
esac
exit 0
EOF
    chmod +x "${bindir}/datasafed" "${bindir}/wal-g"
  }

  run_full_delete() {
    (cd "${tmpdir}" && bash "${dataprotection_dir}/wal-g-delete.sh")
  }

  run_archive_delete() {
    (cd "${tmpdir}" && bash "${dataprotection_dir}/wal-g-archive-delete.sh")
  }

  It "fails when the full-backup repository lookup fails"
    export DATASAFED_LIST_EXIT=41
    When call run_full_delete
    The status should eq 41
  End

  It "fails when deleting the referenced WAL-G base backup fails"
    export WALG_TARGET_EXIT=42
    When call run_full_delete
    The status should eq 42
    The output should include "delete base_00000001"
  End

  It "fails when archive garbage collection fails"
    export WALG_ARCHIVE_EXIT=43
    When call run_archive_delete
    The status should eq 43
  End

  It "succeeds after all full-backup repository cleanup steps succeed"
    When call run_full_delete
    The status should eq 0
    The output should include "delete outdated WAL archive"
  End

  It "succeeds after all archive repository cleanup steps succeed"
    When call run_archive_delete
    The status should eq 0
  End
End
