# shellcheck shell=bash

Describe "dataprotection/pg-basebackup-restore.sh"

  script_path() {
    printf "%s" "../dataprotection/pg-basebackup-restore.sh"
  }

  setup() {
    tmpdir=$(mktemp -d -t pg-basebackup-restore-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"

    VOLUME_DATA_DIR="${tmpdir}/pgdata"
    DATA_DIR="${VOLUME_DATA_DIR}/pgroot/data"
    RESTORE_SCRIPT_DIR="${VOLUME_DATA_DIR}/kb_restore"
    DP_DATASAFED_BIN_PATH="${bindir}"
    DP_BACKUP_BASE_PATH="/backup"
    DP_BACKUP_NAME="backup-test"
    export PATH CALL_LOG VOLUME_DATA_DIR DATA_DIR RESTORE_SCRIPT_DIR DP_DATASAFED_BIN_PATH \
      DP_BACKUP_BASE_PATH DP_BACKUP_NAME
    unset DATASAFED_LIST_OUT TAR_CREATE_PGDATA 2>/dev/null || true
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
    for item in ${DATASAFED_LIST_OUT:-}; do
      if [ "$item" = "$2" ]; then
        printf '%s\n' "$item"
      fi
    done
    ;;
  pull)
    printf '%s\n' "archive bytes"
    ;;
esac
EOF
    cat > "${bindir}/tar" <<'EOF'
#!/bin/sh
printf 'tar %s\n' "$*" >> "${CALL_LOG}"
dest=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-C" ]; then
    shift
    dest=$1
  fi
  shift || break
done
[ -n "$dest" ] || exit 1
if [ "${TAR_CREATE_PGDATA:-1}" = "1" ]; then
  mkdir -p "$dest/base" "$dest/global" "$dest/pg_wal"
  printf '18\n' > "$dest/PG_VERSION"
  printf '{"WAL-Ranges":[{"End-LSN":"0/5000028"}]}\n' > "$dest/backup_manifest"
fi
cat > /dev/null
EOF
    cat > "${bindir}/gunzip" <<'EOF'
#!/bin/sh
cat
EOF
    cat > "${bindir}/pg_waldump" <<'EOF'
#!/bin/sh
echo "rmgr: Transaction len (rec/tot): 0/0, tx: 1, lsn: 0/5000028, prev 0/0"
EOF
    chmod +x "${bindir}/datasafed" "${bindir}/tar" "${bindir}/gunzip" "${bindir}/pg_waldump"
  }

  call_log() {
    cat "${CALL_LOG}"
  }

  restore_hook_syntax_status() {
    bash -n "${RESTORE_SCRIPT_DIR}/kb_restore.sh" >/dev/null 2>&1
    printf "%s" "$?"
  }

  restore_hook_primary_status() {
    bash "${RESTORE_SCRIPT_DIR}/kb_restore.sh" >/dev/null 2>&1
    printf "%s" "$?"
  }

  It "restores the modern zstd archive into pgroot/data and leaves the volume root clean"
    export DATASAFED_LIST_OUT="backup-test.tar.zst"
    When run bash "$(script_path)"
    The status should eq 0
    The output should include "done!"
    The result of function call_log should include "tar -xvf - -C ${DATA_DIR}/"
    The path "${DATA_DIR}/PG_VERSION" should be exist
    The path "${DATA_DIR}/base" should be directory
    The path "${DATA_DIR}/global" should be directory
    The path "${DATA_DIR}/pg_wal" should be directory
    The path "${VOLUME_DATA_DIR}/PG_VERSION" should not be exist
    The path "${VOLUME_DATA_DIR}/base" should not be exist
    The path "${RESTORE_SCRIPT_DIR}/kb_restore.signal" should be exist
    The path "${RESTORE_SCRIPT_DIR}/kb_restore.sh" should be executable
    The contents of file "${RESTORE_SCRIPT_DIR}/kb_restore.sh" should include "DATA_DIR=\"${DATA_DIR}\""
    The contents of file "${RESTORE_SCRIPT_DIR}/kb_restore.sh" should include "PG_VERSION base global pg_wal"
    The contents of file "${RESTORE_SCRIPT_DIR}/kb_restore.sh" should include "--replica"
    The contents of file "${RESTORE_SCRIPT_DIR}/kb_restore.sh" should include "standby.signal"
    The contents of file "${RESTORE_SCRIPT_DIR}/kb_restore.sh" should include 'rm -f "${RESTORE_SCRIPT_DIR}/kb_restore.signal"'
    The result of function restore_hook_syntax_status should eq 0
    touch "${DATA_DIR}/standby.signal" "${DATA_DIR}/recovery.signal"
    The result of function restore_hook_primary_status should eq 0
    The path "${RESTORE_SCRIPT_DIR}/kb_restore.signal" should not be exist
    The path "${DATA_DIR}/standby.signal" should not be exist
    The path "${DATA_DIR}/recovery.signal" should not be exist
  End

  It "fails when DATA_DIR does not match the PostgreSQL volume data subdirectory"
    export DATASAFED_LIST_OUT="backup-test.tar.zst"
    DATA_DIR="${VOLUME_DATA_DIR}"
    export DATA_DIR
    When run bash "$(script_path)"
    The status should be failure
    The error should include "DATA_DIR must be ${VOLUME_DATA_DIR}/pgroot/data"
    The result of function call_log should not include "datasafed pull"
  End

  It "fails when no supported basebackup artifact exists"
    export DATASAFED_LIST_OUT=""
    When run bash "$(script_path)"
    The status should be failure
    The error should include "no supported pg-basebackup artifact found"
    The output should not include "done!"
  End

  It "fails when the restored payload is not a PostgreSQL data directory"
    export DATASAFED_LIST_OUT="backup-test.tar.zst"
    export TAR_CREATE_PGDATA=0
    When run bash "$(script_path)"
    The status should be failure
    The error should include "invalid PostgreSQL data directory"
    The error should include "PG_VERSION"
    The output should not include "done!"
  End

  It "fails when PostgreSQL data files are present at the volume root"
    export DATASAFED_LIST_OUT="backup-test.tar.zst"
    mkdir -p "${VOLUME_DATA_DIR}/base"
    printf '18\n' > "${VOLUME_DATA_DIR}/PG_VERSION"
    When run bash "$(script_path)"
    The status should be failure
    The error should include "PostgreSQL data files were found at volume root"
    The output should not include "done!"
  End
End
