# shellcheck shell=bash

Describe "WAL-G backup connection contract"
  setup() {
    tmpdir=$(mktemp -d -t pg-walg-backup-XXXXXX)
    bindir="${tmpdir}/bin"
    dataprotection_dir=$(cd ../dataprotection && pwd)
    mkdir -p "${bindir}" "${tmpdir}/volume" "${tmpdir}/data"
    PATH="${bindir}:${PATH}"
    CALL_LOG="${tmpdir}/calls.log"
    : > "${CALL_LOG}"
    DP_DATASAFED_BIN_PATH="${bindir}"
    DP_BACKUP_BASE_PATH="/repository/current"
    DP_BACKUP_NAME="backup-test"
    DP_PARENT_BACKUP_NAME="parent"
    DP_BACKUP_INFO_FILE="${tmpdir}/backup-info"
    DP_DB_PASSWORD="secret"
    DP_DB_USER="postgres"
    DP_DB_HOST="postgres.example.test"
    DP_DB_PORT="6432"
    VOLUME_DATA_DIR="${tmpdir}/volume"
    DATA_DIR="${tmpdir}/data"
    export PATH CALL_LOG DP_DATASAFED_BIN_PATH DP_BACKUP_BASE_PATH \
      DP_BACKUP_NAME DP_PARENT_BACKUP_NAME DP_BACKUP_INFO_FILE \
      DP_DB_PASSWORD DP_DB_USER DP_DB_HOST DP_DB_PORT VOLUME_DATA_DIR DATA_DIR
    unset DATASAFED_LIST_EXIT FAIL_BACKUP_PUSH FAIL_REPO_SENTINEL_PUSH \
      FAIL_SWITCH_WAL MV_EXIT 2>/dev/null || true
    write_stubs
  }

  cleanup() {
    rm -rf "${tmpdir}"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  write_stubs() {
    cat > "${bindir}/cp" <<'EOF'
#!/bin/sh
printf 'cp %s\n' "$*" >> "${CALL_LOG}"
exit 0
EOF
    cat > "${bindir}/psql" <<'EOF'
#!/bin/sh
printf 'psql %s\n' "$*" >> "${CALL_LOG}"
case "$*" in
  *archive_command*) printf '%s\n' 'wal-g wal-push %p' ;;
  *pg_switch_wal*)
    if [ "${FAIL_SWITCH_WAL:-0}" -eq 1 ]; then
      exit 2
    fi
    ;;
esac
EOF
    cat > "${bindir}/wal-g" <<'EOF'
#!/bin/sh
printf 'wal-g PGHOST=%s PGUSER=%s PGPORT=%s args=%s\n' \
  "${PGHOST}" "${PGUSER}" "${PGPORT}" "$*" >> "${CALL_LOG}"
printf '%s\n' 'Wrote backup with name base_000000010000000000000001'
if [ "${FAIL_BACKUP_PUSH:-0}" -eq 1 ]; then
  exit 42
fi
EOF
    cat > "${bindir}/datasafed" <<'EOF'
#!/bin/sh
printf 'datasafed %s\n' "$*" >> "${CALL_LOG}"
case "$1" in
  list)
    if [ "${DATASAFED_LIST_EXIT:-0}" -ne 0 ]; then
      exit "${DATASAFED_LIST_EXIT}"
    fi
    printf '%s\n' "$2"
    ;;
  push)
    if [ "${FAIL_REPO_SENTINEL_PUSH:-0}" -eq 1 ] && [ "$3" = "wal-g-backup-repo.path" ]; then
      exit 43
    fi
    cat > /dev/null
    ;;
  pull)
    case "$2" in
      wal-g-backup-name) printf '%s\n' 'base_parent' > "$3" ;;
      *) printf '%s\n' '{"FinishTime":"2026-01-01T00:01:00Z","StartTime":"2026-01-01T00:00:00Z","CompressedSize":42}' > "$3" ;;
    esac
    ;;
esac
EOF
    cat > "${bindir}/jq" <<'EOF'
#!/bin/sh
case "$*" in
  *FinishTime*) printf '%s\n' '2026-01-01T00:01:00Z' ;;
  *StartTime*) printf '%s\n' '2026-01-01T00:00:00Z' ;;
  *CompressedSize*) printf '%s\n' '42' ;;
esac
EOF
    cat > "${bindir}/mv" <<'EOF'
#!/bin/sh
if [ "${MV_EXIT:-0}" -ne 0 ]; then
  exit "${MV_EXIT}"
fi
exec /bin/mv "$@"
EOF
    chmod +x "${bindir}/cp" "${bindir}/psql" "${bindir}/wal-g" \
      "${bindir}/datasafed" "${bindir}/jq" "${bindir}/mv"
  }

  call_log() {
    cat "${CALL_LOG}"
  }

  run_backup() {
    (cd "${tmpdir}" && bash "${dataprotection_dir}/$1")
  }

  run_backup_with_existence_observer() {
    local script="$1"
    (
      cd "${tmpdir}" || exit 1
      echo() {
        case "$1" in
          '{"totalSize"'*) /bin/sleep 0.2 ;;
        esac
        builtin echo "$@"
      }
      (
        for _ in {1..200}; do
          if [[ -e "${DP_BACKUP_INFO_FILE}" ]]; then
            /usr/bin/wc -c < "${DP_BACKUP_INFO_FILE}" > "${tmpdir}/observed-bytes"
            exit 0
          fi
          /bin/sleep 0.01
        done
        printf '0\n' > "${tmpdir}/observed-bytes"
        exit 1
      ) &
      observer_pid=$!
      # shellcheck disable=SC1090
      . "${dataprotection_dir}/${script}"
      wait "${observer_pid}"
    )
  }

  observed_bytes() {
    tr -d '[:space:]' < "${tmpdir}/observed-bytes"
  }

  backup_info_temp_count() {
    find "${tmpdir}" -maxdepth 1 -name 'backup-info.tmp.*' -print | wc -l | tr -d '[:space:]'
  }

  It "executes full backup and WAL switch against the ActionSet endpoint"
    When call run_backup "wal-g-backup.sh"
    The status should eq 0
    The result of function call_log should include "psql -h postgres.example.test -U postgres -p 6432 -d postgres"
    The result of function call_log should include "wal-g PGHOST=postgres.example.test PGUSER=postgres PGPORT=6432"
    The result of function call_log should not include "CLUSTER_COMPONENT_NAME"
  End

  It "fails an incremental backup before publication when the parent sentinel lookup fails"
    export DATASAFED_LIST_EXIT=41
    When call run_backup "wal-g-incremental-backup.sh"
    The status should be failure
    The path "${DP_BACKUP_INFO_FILE}.exit" should be file
    The result of function call_log should not include "wal-g PGHOST="
  End

  It "fails an incremental backup before backup-push when repository sentinel publication fails"
    export FAIL_REPO_SENTINEL_PUSH=1
    When call run_backup "wal-g-incremental-backup.sh"
    The status should be failure
    The path "${DP_BACKUP_INFO_FILE}.exit" should be file
    The result of function call_log should not include "wal-g PGHOST="
  End

  It "fails an incremental backup when backup-push returns nonzero after writing a backup name"
    export FAIL_BACKUP_PUSH=1
    When call run_backup "wal-g-incremental-backup.sh"
    The status should be failure
    The path "${DP_BACKUP_INFO_FILE}.exit" should be file
    The result of function call_log should not include "pg_switch_wal"
  End

  It "executes incremental backup and WAL switch against the ActionSet endpoint"
    When call run_backup "wal-g-incremental-backup.sh"
    The status should eq 0
    The result of function call_log should include "psql -h postgres.example.test -U postgres -p 6432 -d postgres"
    The result of function call_log should include "wal-g PGHOST=postgres.example.test PGUSER=postgres PGPORT=6432"
    The result of function call_log should not include "CLUSTER_COMPONENT_NAME"
  End

  It "fails a full backup when the WAL switch control command fails"
    export FAIL_SWITCH_WAL=1
    When call run_backup "wal-g-backup.sh"
    The status should be failure
    The output should include "failed with exit code 2"
    The path "${DP_BACKUP_INFO_FILE}.exit" should be file
  End

  It "fails an incremental backup when the WAL switch control command fails"
    export FAIL_SWITCH_WAL=1
    When call run_backup "wal-g-incremental-backup.sh"
    The status should be failure
    The output should include "failed with exit code 2"
    The path "${DP_BACKUP_INFO_FILE}.exit" should be file
  End

  It "publishes complete full-backup metadata before the final path is visible"
    When call run_backup_with_existence_observer "wal-g-backup.sh"
    The status should eq 0
    The result of function observed_bytes should not eq 0
    The contents of file "${DP_BACKUP_INFO_FILE}" should include '"wal-g-backup-name":"base_000000010000000000000001"'
  End

  It "publishes complete incremental metadata before the final path is visible"
    When call run_backup_with_existence_observer "wal-g-incremental-backup.sh"
    The status should eq 0
    The result of function observed_bytes should not eq 0
    The contents of file "${DP_BACKUP_INFO_FILE}" should include '"wal-g-backup-name":"base_000000010000000000000001"'
  End

  It "fails full metadata publication without leaving final or temporary metadata"
    export MV_EXIT=7
    When call run_backup "wal-g-backup.sh"
    The status should be failure
    The path "${DP_BACKUP_INFO_FILE}" should not be exist
    The path "${DP_BACKUP_INFO_FILE}.exit" should be file
    The result of function backup_info_temp_count should eq 0
  End

  It "fails incremental metadata publication without leaving final or temporary metadata"
    export MV_EXIT=7
    When call run_backup "wal-g-incremental-backup.sh"
    The status should be failure
    The path "${DP_BACKUP_INFO_FILE}" should not be exist
    The path "${DP_BACKUP_INFO_FILE}.exit" should be file
    The result of function backup_info_temp_count should eq 0
  End
End
