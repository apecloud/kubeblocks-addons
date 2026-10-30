# shellcheck shell=sh

Describe "dataprotection/wal-g-restore.sh sentinel preflight"

  setup() {
    tmpdir=$(mktemp -d -t pg-walg-restore-preflight-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"
    DATA_DIR="${tmpdir}/pgdata"
    RESTORE_SCRIPT_DIR="${tmpdir}/restore-script"
    VOLUME_DATA_DIR="${tmpdir}/volume"
    DP_DATASAFED_BIN_PATH="${bindir}"
    DP_BACKUP_BASE_PATH="/repo/backup-test"
    DP_RESTORE_TIMESTAMP="1"
    dataprotection_dir=$(cd ../dataprotection && pwd)
    mkdir -p "${DATA_DIR}"
    printf '%s\n' original > "${DATA_DIR}/original.marker"
    export PATH CALL_LOG DATA_DIR RESTORE_SCRIPT_DIR VOLUME_DATA_DIR \
      DP_DATASAFED_BIN_PATH DP_BACKUP_BASE_PATH DP_RESTORE_TIMESTAMP
    unset DATASAFED_LIST_EXIT DATASAFED_PULL_EXIT DATASAFED_SKIP_WRITE \
      MISSING_BACKUP_NAME SENTINELS_PRESENT 2>/dev/null || true
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
case "$1" in
  list)
    if [ "${DATASAFED_LIST_EXIT:-0}" -ne 0 ]; then
      exit "${DATASAFED_LIST_EXIT}"
    fi
    if [ "${SENTINELS_PRESENT:-0}" -eq 1 ]; then
      if [ "${MISSING_BACKUP_NAME:-0}" -ne 1 ] || [ "$2" != "wal-g-backup-name" ]; then
        printf '%s\n' "$2"
      fi
    fi
    ;;
  pull)
    if [ "${DATASAFED_PULL_EXIT:-0}" -ne 0 ]; then
      exit "${DATASAFED_PULL_EXIT}"
    fi
    if [ "${DATASAFED_SKIP_WRITE:-0}" -eq 1 ]; then
      exit 0
    fi
    case "$2" in
      wal-g-backup-repo.path) printf '%s\n' /repo/wal-g > "$3" ;;
      wal-g-backup-name) printf '%s\n' base_00000001 > "$3" ;;
    esac
    ;;
esac
EOF
    cat > "${bindir}/wal-g" <<'EOF'
#!/bin/sh
printf 'wal-g %s\n' "$*" >> "${CALL_LOG}"
if [ "$1" = "backup-fetch" ]; then
  mkdir -p "$2"
  printf '%s\n' fetched > "$2/fetched.marker"
fi
EOF
    chmod +x "${bindir}/datasafed" "${bindir}/wal-g"
  }

  run_restore() {
    (cd "${tmpdir}" && bash "${dataprotection_dir}/wal-g-restore.sh")
  }

  call_log() {
    cat "${CALL_LOG}"
  }

  It "fails before replacing data when sentinel metadata is missing"
    When call run_restore
    The status should be failure
    The error should include "missing WAL-G backup repository sentinel"
    The path "${DATA_DIR}/original.marker" should be exist
    The result of function call_log should not include "wal-g backup-fetch"
  End

  It "fails before replacing data when the backup name sentinel is missing"
    export SENTINELS_PRESENT=1 MISSING_BACKUP_NAME=1
    When call run_restore
    The status should be failure
    The error should include "missing WAL-G backup name sentinel"
    The path "${DATA_DIR}/original.marker" should be exist
    The result of function call_log should not include "wal-g backup-fetch"
  End

  It "fails before replacing data when sentinel lookup is unavailable"
    export DATASAFED_LIST_EXIT=41
    When call run_restore
    The status should be failure
    The error should include "failed to list WAL-G sentinel wal-g-backup-repo.path"
    The path "${DATA_DIR}/original.marker" should be exist
    The result of function call_log should not include "wal-g backup-fetch"
  End

  It "fails before replacing data when sentinel download is unavailable"
    export SENTINELS_PRESENT=1 DATASAFED_PULL_EXIT=42
    When call run_restore
    The status should be failure
    The error should include "failed to pull WAL-G sentinel wal-g-backup-repo.path"
    The path "${DATA_DIR}/original.marker" should be exist
    The result of function call_log should not include "wal-g backup-fetch"
  End

  It "fails before replacing data when downloaded sentinel content cannot be read"
    export SENTINELS_PRESENT=1 DATASAFED_SKIP_WRITE=1
    When call run_restore
    The status should be failure
    The error should include "failed to read WAL-G sentinel wal-g-backup-repo.path"
    The path "${DATA_DIR}/original.marker" should be exist
    The result of function call_log should not include "wal-g backup-fetch"
  End

  It "fetches the named base backup after both sentinels are validated"
    export SENTINELS_PRESENT=1
    When call run_restore
    The status should eq 0
    The path "${DATA_DIR}/fetched.marker" should be exist
    The result of function call_log should include "wal-g backup-fetch ${DATA_DIR} base_00000001"
  End
End
