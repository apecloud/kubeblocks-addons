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
    unset DATASAFED_LIST_ROOT DATASAFED_LIST_DIR DATASAFED_LIST_DIR_20260816 \
      DATASAFED_LIST_DIR_20260817 DATASAFED_ROOT_LIST_EXIT \
      DATASAFED_DIR_LIST_EXIT DATASAFED_LIST_FAIL_PATH \
      DATASAFED_PULL_FAIL_OBJECT DATE_FAIL_VALUE \
      PG_WALDUMP_FAIL_OBJECT 2>/dev/null || true

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
      if [ "${DATASAFED_ROOT_LIST_EXIT:-0}" -ne 0 ]; then
        exit "${DATASAFED_ROOT_LIST_EXIT}"
      fi
      printf '%s\n' "${DATASAFED_LIST_ROOT:-}"
    else
      if [ "$2" = "${DATASAFED_LIST_FAIL_PATH:-}" ]; then
        exit 43
      fi
      if [ "${DATASAFED_DIR_LIST_EXIT:-0}" -ne 0 ]; then
        exit "${DATASAFED_DIR_LIST_EXIT}"
      fi
      case "$2" in
        20260816/) printf '%s\n' "${DATASAFED_LIST_DIR_20260816:-${DATASAFED_LIST_DIR:-}}" ;;
        20260817/) printf '%s\n' "${DATASAFED_LIST_DIR_20260817:-${DATASAFED_LIST_DIR:-}}" ;;
        *) printf '%s\n' "${DATASAFED_LIST_DIR:-}" ;;
      esac
    fi
    ;;
  pull)
    if [ "$4" = "${DATASAFED_PULL_FAIL_OBJECT:-}" ]; then
      exit 44
    fi
    # last arg is the destination file
    for arg; do dest="$arg"; done
    echo "wal-bytes" > "$dest"
    ;;
esac
EOF
    cat > "${bindir}/pg_waldump" <<'EOF'
#!/bin/sh
wal_name=${1##*/}
if [ "$wal_name" = "${PG_WALDUMP_FAIL_OBJECT:-}" ]; then
  exit 46
fi
echo "rmgr: Transaction desc: COMMIT 2026-01-01 00:00:00 UTC; inval msgs"
EOF
    # minimal GNU `date -d` emulation with canned epochs; the pair is chosen
    # so the 9-digit restore_time vs 10-digit commit epoch discriminates a
    # lexicographic comparison from a numeric one
    cat > "${bindir}/date" <<'EOF'
#!/bin/sh
if [ "$1" = "-d" ]; then
  arg=$2; shift 2; fmt=${1:-+%s}
  if [ "$arg" = "${DATE_FAIL_VALUE:-}" ]; then
    exit 45
  fi
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

  first_pulled_archive() {
    awk '/^datasafed pull / { print $5; exit }' "${CALL_LOG}"
  }

  call_log() {
    cat "${CALL_LOG}"
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

    It "fails before repository access when live and staged data directories both exist"
      mkdir -p "${DATA_DIR}/pg_wal" "${DATA_DIR}.old/pg_wal"
      echo live > "${DATA_DIR}/pg_wal/000000010000000000000001"
      echo staged > "${DATA_DIR}.old/pg_wal/000000010000000000000001"
      When run bash "${concat}"
      The status should be failure
      The output should include "both ${DATA_DIR} and ${DATA_DIR}.old exist"
      The result of function call_log should not include "datasafed"
      The path "${DATA_DIR}" should be exist
      The path "${DATA_DIR}.old/data" should not be exist
    End

    It "continues preparation after the target WAL is found before another archive directory"
      mkdir -p "${DATA_DIR}/pg_wal"
      echo x > "${DATA_DIR}/pg_wal/000000010000000000000001"
      export DATASAFED_LIST_ROOT="waldir-one/ waldir-two/"
      export DATASAFED_LIST_DIR="000000010000000000000002.zst"
      DP_RESTORE_TIME="2001-01-01 00:00:00"
      export DP_RESTORE_TIME
      When run bash "${concat}"
      The status should eq 0
      The output should include "exit when reaching the target time log."
      The output should include "done."
      The path "${CONF_DIR}/recovery.conf" should be exist
      The path "${DATA_DIR}.old" should be exist
    End

    It "ignores unrelated local files when selecting the starting WAL"
      mkdir -p "${DATA_DIR}/pg_wal"
      echo x > "${DATA_DIR}/pg_wal/000000010000000000000001"
      echo x > "${DATA_DIR}/pg_wal/README"
      export DATASAFED_LIST_ROOT="20260816/"
      export DATASAFED_LIST_DIR="000000010000000000000002.zst"
      DP_RESTORE_TIME="2001-01-01 00:00:00"
      export DP_RESTORE_TIME
      When run bash "${concat}"
      The status should eq 0
      The output should include "fetch-wal-log ${PITR_DIR} 000000010000000000000001"
      The result of function first_pulled_archive should eq "000000010000000000000002.zst"
      The path "${DATA_DIR}.old" should be exist
    End

    It "fails before repository access when the recovery target timestamp cannot be formatted"
      mkdir -p "${DATA_DIR}/pg_wal"
      echo x > "${DATA_DIR}/pg_wal/000000010000000000000001"
      DP_RESTORE_TIMESTAMP="invalid-epoch"
      export DP_RESTORE_TIMESTAMP DATE_FAIL_VALUE="@invalid-epoch"
      When run bash "${concat}"
      The status should be failure
      The output should include "failed to format PITR recovery timestamp invalid-epoch"
      The result of function call_log should not include "datasafed"
      The path "${DATA_DIR}" should be exist
      The path "${DATA_DIR}.old" should not be exist
    End

    It "fails before staging data when the WAL repository root cannot be listed"
      mkdir -p "${DATA_DIR}/pg_wal"
      echo x > "${DATA_DIR}/pg_wal/000000010000000000000001"
      export DATASAFED_ROOT_LIST_EXIT=42
      When run bash "${concat}"
      The status should be failure
      The output should include "failed to list the WAL archive root"
      The path "${DATA_DIR}" should be exist
      The path "${DATA_DIR}.old" should not be exist
    End

    It "fails before staging data when a WAL archive directory cannot be listed"
      mkdir -p "${DATA_DIR}/pg_wal"
      echo x > "${DATA_DIR}/pg_wal/000000010000000000000001"
      export DATASAFED_LIST_ROOT="waldir/"
      export DATASAFED_DIR_LIST_EXIT=43
      When run bash "${concat}"
      The status should be failure
      The output should include "failed to list WAL archive directory waldir/"
      The path "${DATA_DIR}" should be exist
      The path "${DATA_DIR}.old" should not be exist
    End

    It "ignores unrelated repository root objects before listing archive directories"
      mkdir -p "${DATA_DIR}/pg_wal"
      echo x > "${DATA_DIR}/pg_wal/000000010000000000000001"
      export DATASAFED_LIST_ROOT="!README
20260816/"
      export DATASAFED_LIST_FAIL_PATH="!README"
      export DATASAFED_LIST_DIR="000000010000000000000002.zst"
      DP_RESTORE_TIME="2001-01-01 00:00:00"
      export DP_RESTORE_TIME
      When run bash "${concat}"
      The status should eq 0
      The result of function first_pulled_archive should eq "000000010000000000000002.zst"
      The result of function call_log should not include "datasafed list !README"
      The path "${DATA_DIR}.old" should be exist
    End
  End

  Describe "fetch-wal-log()"
    Include ../dataprotection/common-scripts.sh
    Include ../dataprotection/postgresql-fetch-wal-log.sh

    It "fails before repository access when the restore target time cannot be parsed"
      export DATE_FAIL_VALUE="invalid-target"
      When call fetch-wal-log "${tmpdir}/dest" "000000010000000000000001" "invalid-target" true
      The status should be failure
      The output should include "failed to parse PITR restore time invalid-target"
      The result of function call_log should not include "datasafed"
    End

    It "fails before repository access when the WAL destination cannot be created"
      blocked_parent="${tmpdir}/blocked"
      printf 'not-a-directory\n' > "${blocked_parent}"
      When call fetch-wal-log "${blocked_parent}/dest" "000000010000000000000001" "2026-01-01 00:00:00" true
      The status should be failure
      The output should include "failed to create WAL destination ${blocked_parent}/dest"
      The result of function call_log should not include "datasafed"
    End

    It "fetches older archive directories before newer ones when the repository listing is unsorted"
      export DATASAFED_LIST_ROOT="20260817/
20260816/"
      export DATASAFED_LIST_DIR_20260816="000000010000000000000002.zst"
      export DATASAFED_LIST_DIR_20260817="000000010000000000000003.zst"
      When call fetch-wal-log "${tmpdir}/dest" "000000010000000000000001" "2026-01-01 00:00:00" true
      The status should eq 0
      The result of function first_pulled_archive should eq "000000010000000000000002.zst"
    End

    It "fetches older WAL objects before newer ones when a directory listing is unsorted"
      export DATASAFED_LIST_ROOT="20260816/"
      export DATASAFED_LIST_DIR="000000010000000000000003.zst
000000010000000000000002.zst"
      When call fetch-wal-log "${tmpdir}/dest" "000000010000000000000001" "2026-01-01 00:00:00" true
      The status should eq 0
      The result of function first_pulled_archive should eq "000000010000000000000002.zst"
    End

    It "ignores unrelated compressed objects before fetching WAL archives"
      export DATASAFED_LIST_ROOT="20260816/"
      export DATASAFED_LIST_DIR="000000010000000000000001metadata.zst
000000010000000000000002.zst"
      When call fetch-wal-log "${tmpdir}/dest" "000000010000000000000001" "2001-01-01 00:00:00" true
      The status should eq 0
      The result of function first_pulled_archive should eq "000000010000000000000002.zst"
      The result of function call_log should not include "datasafed pull -d zstd 000000010000000000000001metadata.zst"
    End

    It "pulls timeline history without inspecting it as a WAL segment"
      export DATASAFED_LIST_ROOT="20260816/"
      export DATASAFED_LIST_DIR="000000010000000000000002.zst
00000002.history.zst"
      export PG_WALDUMP_FAIL_OBJECT="00000002.history"
      When call fetch-wal-log "${tmpdir}/dest" "000000010000000000000001" "2026-01-01 00:00:00" true
      The status should eq 0
      The output should not include "failed to inspect WAL 00000002.history"
      The path "${tmpdir}/dest/00000002.history" should be exist
    End

    It "fetches current timeline history even when it sorts below the start WAL"
      export DATASAFED_LIST_ROOT="20260816/"
      export DATASAFED_LIST_DIR="00000002.history.zst
000000020000000000000001.zst"
      When call fetch-wal-log "${tmpdir}/dest" "000000020000000000000001" "2026-01-01 00:00:00" true
      The status should eq 0
      The path "${tmpdir}/dest/00000002.history" should be exist
      The result of function call_log should include "datasafed pull -d zstd 00000002.history.zst"
    End

    It "fetches current timeline history from a history-only archive directory"
      export DATASAFED_LIST_ROOT="20260816/"
      export DATASAFED_LIST_DIR="00000002.history.zst"
      When call fetch-wal-log "${tmpdir}/dest" "000000020000000000000001" "2026-01-01 00:00:00" true
      The status should eq 0
      The path "${tmpdir}/dest/00000002.history" should be exist
      The result of function call_log should include "datasafed pull -d zstd 00000002.history.zst"
    End

    It "stops at the first WAL pull failure instead of crossing an archive gap"
      export DATASAFED_LIST_ROOT="20260816/"
      export DATASAFED_LIST_DIR="000000010000000000000002.zst
000000010000000000000003.zst"
      export DATASAFED_PULL_FAIL_OBJECT="000000010000000000000002.zst"
      When call fetch-wal-log "${tmpdir}/dest" "000000010000000000000001" "2026-01-01 00:00:00" true
      The status should be failure
      The output should include "failed to pull WAL archive 000000010000000000000002.zst"
      The result of function call_log should not include "datasafed pull -d zstd 000000010000000000000003.zst"
    End

    It "stops when a WAL commit timestamp cannot be parsed"
      export DATASAFED_LIST_ROOT="20260816/"
      export DATASAFED_LIST_DIR="000000010000000000000002.zst
000000010000000000000003.zst"
      export DATE_FAIL_VALUE="2026-01-01 00:00:00 UTC"
      When call fetch-wal-log "${tmpdir}/dest" "000000010000000000000001" "2001-01-01 00:00:00" true
      The status should be failure
      The output should include "failed to parse commit time for WAL 000000010000000000000002"
      The result of function call_log should not include "datasafed pull -d zstd 000000010000000000000003.zst"
    End

    It "stops when an archived WAL cannot be inspected"
      export DATASAFED_LIST_ROOT="20260816/"
      export DATASAFED_LIST_DIR="000000010000000000000002.zst
000000010000000000000003.zst"
      export PG_WALDUMP_FAIL_OBJECT="000000010000000000000002"
      When call fetch-wal-log "${tmpdir}/dest" "000000010000000000000001" "2001-01-01 00:00:00" true
      The status should be failure
      The output should include "failed to inspect WAL 000000010000000000000002"
      The result of function call_log should not include "datasafed pull -d zstd 000000010000000000000003.zst"
    End

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
