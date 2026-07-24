# shellcheck shell=bash
# Tests the PITR restore path: the generated restore_command must be
# replayable (cp, not mv — a mid-recovery restart re-requests consumed
# segments), and fetch-wal-log's stop condition must compare epochs
# numerically. The prepareData script runs top-level, so tests execute the
# same concatenation the ActionSet builds (set -e + common + fetch + restore).

Describe "dataprotection PITR restore"

  setup() {
    tmpdir=$(mktemp -d -t pg-pitr-restore-XXXXXX)
    bindir="${tmpdir}/bin"
    mkdir -p "${bindir}"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"

    DATA_DIR="${tmpdir}/pgdata/data"
    PITR_DIR="${tmpdir}/pitr"
    CONF_DIR="${tmpdir}/conf"
    RESTORE_SCRIPT_DIR="${tmpdir}/kb_restore"
    DP_RESTORE_TIME="2026-01-01 00:00:00"
    DP_RESTORE_TIMESTAMP="1767225600"
    DP_BACKUP_BASE_PATH="/backup"
    DP_DATASAFED_BIN_PATH="${bindir}"
    export PATH CALL_LOG DATA_DIR PITR_DIR CONF_DIR RESTORE_SCRIPT_DIR \
      DP_RESTORE_TIME DP_RESTORE_TIMESTAMP DP_BACKUP_BASE_PATH DP_DATASAFED_BIN_PATH
    unset DATASAFED_LIST_ROOT DATASAFED_LIST_DIR 2>/dev/null || true

    write_stubs
    build_concat
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
    if [ "$2" = "/" ]; then
      printf '%s\n' "${DATASAFED_LIST_ROOT:-}"
    else
      printf '%s\n' "${DATASAFED_LIST_DIR:-}"
    fi
    ;;
  pull)
    # last arg is the destination file
    for arg; do dest="$arg"; done
    echo "wal-bytes" > "$dest"
    ;;
esac
EOF
    cat > "${bindir}/pg_waldump" <<'EOF'
#!/bin/sh
echo "rmgr: Transaction desc: COMMIT 2026-01-01 00:00:00 UTC; inval msgs"
EOF
    # minimal GNU `date -d` emulation with canned epochs; the pair is chosen
    # so the 9-digit restore_time vs 10-digit commit epoch discriminates a
    # lexicographic comparison from a numeric one
    cat > "${bindir}/date" <<'EOF'
#!/bin/sh
if [ "$1" = "-d" ]; then
  arg=$2; shift 2; fmt=${1:-+%s}
  case "$arg" in
    @*) secs=${arg#@} ;;
    "2001-01-01 00:00:00") secs=978307200 ;;
    *2026*) secs=1767225600 ;;
    *) secs=0 ;;
  esac
  case "$fmt" in
    "+%s") echo "$secs" ;;
    *) echo "2026-01-01 00:00:00+00:00" ;;
  esac
else
  exec /bin/date "$@"
fi
EOF
    chmod +x "${bindir}/datasafed" "${bindir}/pg_waldump" "${bindir}/date"
    # the script uses GNU-isms (`ls -I`, `chmod MODE -R`); on BSD hosts route
    # these to coreutils g-variants so local runs match CI behavior
    if ! ls -I x / >/dev/null 2>&1 && command -v gls >/dev/null 2>&1; then
      ln -s "$(command -v gls)" "${bindir}/ls"
      ln -s "$(command -v gchmod)" "${bindir}/chmod"
    fi
  }

  # the same concatenation actionset-postgresql-pitr.yaml builds for prepareData
  build_concat() {
    concat="${tmpdir}/restore-concat.sh"
    {
      echo "set -e"
      cat ../dataprotection/common-scripts.sh; echo
      cat ../dataprotection/postgresql-fetch-wal-log.sh; echo
      cat ../dataprotection/postgresql-pitr-restore.sh; echo
    } > "${concat}"
  }

  Describe "prepareData script (concatenated form)"
    It "generates a replayable cp restore_command and stages the data dir"
      mkdir -p "${DATA_DIR}/pg_wal"
      echo x > "${DATA_DIR}/pg_wal/000000010000000000000001"
      When run bash "${concat}"
      The status should eq 0
      The output should include "done."
      The path "${CONF_DIR}/recovery.conf" should be exist
      The contents of file "${CONF_DIR}/recovery.conf" should include "restore_command='cp ${PITR_DIR}/%f %p'"
      The contents of file "${CONF_DIR}/recovery.conf" should not include "mv "
      The path "${DATA_DIR}.old" should be exist
      The path "${RESTORE_SCRIPT_DIR}/kb_restore.sh" should be exist
    End

    It "retries idempotently when a previous run already staged the data dir"
      mkdir -p "${DATA_DIR}.old/pg_wal"
      echo x > "${DATA_DIR}.old/pg_wal/000000010000000000000001"
      When run bash "${concat}"
      The status should eq 0
      The output should include "done."
      The path "${DATA_DIR}" should not be exist
      The path "${DATA_DIR}.old" should be exist
      The path "${CONF_DIR}/recovery.conf" should be exist
    End
  End

  Describe "fetch-wal-log()"
    Include ../dataprotection/common-scripts.sh
    Include ../dataprotection/postgresql-fetch-wal-log.sh

    It "stops at the target time with numeric epoch comparison (9-digit vs 10-digit)"
      export DATASAFED_LIST_ROOT="waldir/"
      export DATASAFED_LIST_DIR="000000010000000000000002.zst"
      # restore_time 2001 -> 978307200 (9 digits); commit epoch 2026 ->
      # 1767225600 (10 digits). Lexicographic '>' says 1... < 9... and keeps
      # fetching; numeric -gt stops. This example fails on the old code.
      When call fetch-wal-log "${tmpdir}/dest" "000000010000000000000001" "2001-01-01 00:00:00" true
      The output should include "exit when reaching the target time log."
    End
  End
End
