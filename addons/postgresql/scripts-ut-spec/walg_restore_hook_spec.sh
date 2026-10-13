# shellcheck shell=bash

Describe "WAL-G generated restore hooks"

  setup() {
    tmpdir=$(mktemp -d -t pg-walg-restore-hook-XXXXXX)
    bindir="${tmpdir}/bin"
    DATA_DIR="${tmpdir}/pgdata"
    RESTORE_SCRIPT_DIR="${tmpdir}/kb_restore"
    mkdir -p "${bindir}" "${RESTORE_SCRIPT_DIR}"
    PATH="${bindir}:${PATH}"
    export PATH DATA_DIR RESTORE_SCRIPT_DIR
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  extract_hook() {
    local source="$1"
    local destination="$2"

    awk '
      /kb_restore\.sh << '\''EOF'\''/ { capture=1; next }
      capture && /^EOF$/ { exit }
      capture { print }
    ' "$source" \
      | sed \
          -e "s|\${DATA_DIR}|${DATA_DIR}|g" \
          -e "s|\${RESTORE_SCRIPT_DIR}|${RESTORE_SCRIPT_DIR}|g" \
      > "$destination"
    chmod +x "$destination"
  }

  run_hook() {
    local source="$1"
    local hook="${RESTORE_SCRIPT_DIR}/kb_restore.sh"

    extract_hook "$source" "$hook"
    bash "$hook" >/dev/null
  }

  run_normal_restore_hook() {
    run_hook "../dataprotection/wal-g-restore.sh" >/dev/null 2>&1
    printf '%s' "$?"
  }

  It "moves hidden entries and commits the normal WAL-G restore"
    mkdir -p "${DATA_DIR}.old" "${DATA_DIR}"
    printf '18\n' > "${DATA_DIR}.old/PG_VERSION"
    printf 'hidden\n' > "${DATA_DIR}.old/.hidden"
    touch "${RESTORE_SCRIPT_DIR}/kb_restore.signal"
    When call run_hook "../dataprotection/wal-g-restore.sh"
    The status should eq 0
    The path "${DATA_DIR}/PG_VERSION" should be exist
    The path "${DATA_DIR}/.hidden" should be exist
    The path "${DATA_DIR}/.kb_walg_handoff" should be exist
    The path "${DATA_DIR}.old" should not be exist
    The path "${RESTORE_SCRIPT_DIR}/kb_restore.signal" should not be exist
  End

  It "converges after normal WAL-G data moved before signal removal"
    mkdir -p "${DATA_DIR}.old" "${DATA_DIR}"
    printf 'normal\n' > "${DATA_DIR}/.kb_walg_handoff"
    printf '18\n' > "${DATA_DIR}/PG_VERSION"
    touch "${RESTORE_SCRIPT_DIR}/kb_restore.signal"
    When call run_hook "../dataprotection/wal-g-restore.sh"
    The status should eq 0
    The path "${DATA_DIR}/PG_VERSION" should be exist
    The path "${DATA_DIR}/.kb_walg_handoff" should be exist
    The path "${DATA_DIR}.old" should not be exist
    The path "${RESTORE_SCRIPT_DIR}/kb_restore.signal" should not be exist
  End

  It "keeps the signal on sync failure and converges on retry"
    mkdir -p "${DATA_DIR}.old" "${DATA_DIR}"
    printf '18\n' > "${DATA_DIR}.old/PG_VERSION"
    touch "${RESTORE_SCRIPT_DIR}/kb_restore.signal"
    cat > "${bindir}/sync" <<'EOF'
#!/bin/sh
exit 7
EOF
    chmod +x "${bindir}/sync"
    The result of function run_normal_restore_hook should not eq 0
    The path "${RESTORE_SCRIPT_DIR}/kb_restore.signal" should be exist
    The path "${DATA_DIR}/PG_VERSION" should be exist
    The path "${DATA_DIR}/.kb_walg_handoff" should be exist
    The path "${DATA_DIR}.old" should not be exist

    rm -f "${bindir}/sync"
    The result of function run_normal_restore_hook should eq 0
    The path "${RESTORE_SCRIPT_DIR}/kb_restore.signal" should not be exist
    The path "${DATA_DIR}/PG_VERSION" should be exist
    The path "${DATA_DIR}/.kb_walg_handoff" should be exist
  End

  It "converges after failed-restore data moved before signal removal"
    mkdir -p "${DATA_DIR}.failed" "${DATA_DIR}"
    printf 'failed\n' > "${DATA_DIR}/.kb_walg_handoff"
    printf '18\n' > "${DATA_DIR}/PG_VERSION"
    touch "${DATA_DIR}/recovery.signal"
    touch "${RESTORE_SCRIPT_DIR}/kb_restore.signal"
    When call run_hook "../dataprotection/wal-g-restore.sh"
    The status should eq 0
    The path "${DATA_DIR}/PG_VERSION" should be exist
    The path "${DATA_DIR}/recovery.signal" should not be exist
    The path "${DATA_DIR}/.kb_walg_handoff" should be exist
    The path "${DATA_DIR}.failed" should not be exist
    The path "${RESTORE_SCRIPT_DIR}/kb_restore.signal" should not be exist
  End

  It "converges after archive WAL-G data moved before signal removal"
    mkdir -p "${DATA_DIR}.old" "${DATA_DIR}"
    printf 'normal\n' > "${DATA_DIR}/.kb_walg_handoff"
    printf '18\n' > "${DATA_DIR}/PG_VERSION"
    touch "${RESTORE_SCRIPT_DIR}/kb_restore.signal"
    When call run_hook "../dataprotection/wal-g-archive-restore.sh"
    The status should eq 0
    The path "${DATA_DIR}/PG_VERSION" should be exist
    The path "${DATA_DIR}/.kb_walg_handoff" should be exist
    The path "${DATA_DIR}.old" should not be exist
    The path "${RESTORE_SCRIPT_DIR}/kb_restore.signal" should not be exist
  End
End
