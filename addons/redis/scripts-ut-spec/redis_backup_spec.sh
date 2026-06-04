# shellcheck shell=bash
# shellcheck disable=SC2034

if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "redis_backup_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

Describe "Redis Backup Script Tests"
  setup_backup_env() {
    SPEC_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/redis-backup.XXXXXX")"
    export SPEC_TMPDIR
    export PATH="${SPEC_TMPDIR}/bin:${PATH}"
    export DP_BACKUP_INFO_FILE="${SPEC_TMPDIR}/backup.info"
    export DP_DATASAFED_BIN_PATH="${SPEC_TMPDIR}/bin"
    export DP_BACKUP_BASE_PATH="/backup/redis"
    export DP_BACKUP_NAME="redis-backup"
    export DATA_DIR="${SPEC_TMPDIR}/data"
    export MODE="cluster"
    export DP_DB_HOST="redis-0.redis-headless"
    export DP_DB_PORT="6379"
    export DP_DB_PASSWORD=""
    export REDIS_CLI_TLS_CMD=""
    export SENTINEL_POD_FQDN_LIST=""
    export REDIS_CLI_CALL_LOG="${SPEC_TMPDIR}/redis-cli.calls"
    export DATASAFED_CALL_LOG="${SPEC_TMPDIR}/datasafed.calls"
    export REDIS_CLI_INFO_COUNT_FILE="${SPEC_TMPDIR}/redis-cli.info.count"
    export REDIS_CLI_FAIL_STAGE=""

    mkdir -p "${SPEC_TMPDIR}/bin" "${DATA_DIR}"
    printf 'rdb' > "${DATA_DIR}/dump.rdb"
    printf 'nodes' > "${DATA_DIR}/nodes.conf"
    printf 'users' > "${DATA_DIR}/users.acl"

    cat > "${SPEC_TMPDIR}/bin/redis-cli" <<'STUB'
#!/bin/bash
echo "$*" >> "${REDIS_CLI_CALL_LOG}"
case "$*" in
  *"LASTSAVE"*)
    if [ "${REDIS_CLI_FAIL_STAGE}" = "LASTSAVE" ]; then
      echo "Could not connect to Redis at ${DP_DB_HOST}:${DP_DB_PORT}: Temporary failure in name resolution" >&2
      exit 1
    fi
    echo "1710000000"
    ;;
  *"BGSAVE"*)
    if [ "${REDIS_CLI_FAIL_STAGE}" = "BGSAVE" ]; then
      echo "Could not connect to Redis at ${DP_DB_HOST}:${DP_DB_PORT}: Temporary failure in name resolution" >&2
      exit 1
    fi
    echo "Background saving started"
    ;;
  *"INFO persistence"*)
    if [ "${REDIS_CLI_FAIL_STAGE}" = "INFO" ]; then
      count=0
      if [ -f "${REDIS_CLI_INFO_COUNT_FILE}" ]; then
        count="$(cat "${REDIS_CLI_INFO_COUNT_FILE}")"
      fi
      count=$((count + 1))
      echo "${count}" > "${REDIS_CLI_INFO_COUNT_FILE}"
      if [ "${count}" -le 2 ]; then
        echo "Could not connect to Redis at ${DP_DB_HOST}:${DP_DB_PORT}: Temporary failure in name resolution" >&2
        exit 1
      fi
    fi
    printf 'rdb_bgsave_in_progress:0\r\nrdb_last_bgsave_status:ok\r\n'
    ;;
  *)
    echo "unexpected redis-cli command: $*" >&2
    exit 2
    ;;
esac
STUB
    chmod +x "${SPEC_TMPDIR}/bin/redis-cli"

    cat > "${SPEC_TMPDIR}/bin/datasafed" <<'STUB'
#!/bin/bash
echo "$*" >> "${DATASAFED_CALL_LOG}"
case "$1" in
  push)
    if [ "$3" = "-" ]; then
      cat >/dev/null
    fi
    echo "ok"
    ;;
  stat)
    echo "TotalSize 42"
    ;;
  *)
    echo "unexpected datasafed command: $*" >&2
    exit 2
    ;;
esac
STUB
    chmod +x "${SPEC_TMPDIR}/bin/datasafed"
  }
  Before "setup_backup_env"

  cleanup_backup_env() {
    if [ -n "${SPEC_TMPDIR:-}" ] && [ -d "${SPEC_TMPDIR}" ]; then
      rm -rf "${SPEC_TMPDIR}"
    fi
  }
  After "cleanup_backup_env"

  It "fails fast when LASTSAVE cannot connect"
    REDIS_CLI_FAIL_STAGE="LASTSAVE"
    When run source ../dataprotection/backup.sh
    The status should be failure
    The stdout should include "failed with exit code 1"
    The stderr should include "ERROR: redis-cli LASTSAVE failed against redis-0.redis-headless:6379"
    The stderr should include "Temporary failure in name resolution"
    The path "${DP_BACKUP_INFO_FILE}.exit" should be file
    The contents of file "${REDIS_CLI_CALL_LOG}" should include "LASTSAVE"
    The contents of file "${REDIS_CLI_CALL_LOG}" should not include "BGSAVE"
  End

  It "fails fast when BGSAVE cannot connect"
    REDIS_CLI_FAIL_STAGE="BGSAVE"
    When run source ../dataprotection/backup.sh
    The status should be failure
    The stdout should include "failed with exit code 1"
    The stderr should include "ERROR: redis-cli BGSAVE failed against redis-0.redis-headless:6379"
    The stderr should include "Temporary failure in name resolution"
    The path "${DP_BACKUP_INFO_FILE}.exit" should be file
    The contents of file "${REDIS_CLI_CALL_LOG}" should include "LASTSAVE"
    The contents of file "${REDIS_CLI_CALL_LOG}" should include "BGSAVE"
    The contents of file "${REDIS_CLI_CALL_LOG}" should not include "INFO persistence"
  End

  It "fails fast on the first INFO persistence connection failure"
    REDIS_CLI_FAIL_STAGE="INFO"
    When run source ../dataprotection/backup.sh
    The status should be failure
    The stdout should include "failed with exit code 1"
    The stderr should include "ERROR: redis-cli INFO persistence failed against redis-0.redis-headless:6379"
    The stderr should include "Temporary failure in name resolution"
    The path "${DP_BACKUP_INFO_FILE}.exit" should be file
    The contents of file "${REDIS_CLI_INFO_COUNT_FILE}" should eq "1"
  End

  It "writes backup info when Redis control commands and datasafed succeed"
    When run source ../dataprotection/backup.sh
    The status should be success
    The stdout should include "INFO: save data file successfully"
    The stderr should equal ""
    The path "${DP_BACKUP_INFO_FILE}" should be file
    The contents of file "${DP_BACKUP_INFO_FILE}" should include "\"totalSize\":\"42\""
    The contents of file "${REDIS_CLI_CALL_LOG}" should include "LASTSAVE"
    The contents of file "${REDIS_CLI_CALL_LOG}" should include "BGSAVE"
    The contents of file "${REDIS_CLI_CALL_LOG}" should include "INFO persistence"
  End
End
