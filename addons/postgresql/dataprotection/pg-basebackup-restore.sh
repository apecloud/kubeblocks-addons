# shellcheck shell=bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

function remote_file_exists() {
    local out
    out=$(datasafed list "$1")
    if [ "${out}" == "$1" ]; then
        echo "true"
        return
    fi
    echo "false"
}

function validate_data_dir_contract() {
    if [[ -z "${DATA_DIR:-}" ]]; then
        echo "ERROR: DATA_DIR is required for pg-basebackup restore" >&2
        exit 1
    fi

    DATA_DIR="${DATA_DIR%/}"
    if [[ -n "${VOLUME_DATA_DIR:-}" ]]; then
        VOLUME_DATA_DIR="${VOLUME_DATA_DIR%/}"
        local expected_data_dir="${VOLUME_DATA_DIR}/pgroot/data"
        if [[ "${DATA_DIR}" != "${expected_data_dir}" ]]; then
            echo "ERROR: pg-basebackup restore DATA_DIR must be ${expected_data_dir}, got ${DATA_DIR}" >&2
            echo "ERROR: refusing to restore PostgreSQL files into the volume root or an unexpected subdirectory" >&2
            exit 1
        fi
    fi
}

function log_restore_layout() {
    echo "restore layout: VOLUME_DATA_DIR=${VOLUME_DATA_DIR:-<unset>} DATA_DIR=${DATA_DIR}"
    if [[ -n "${VOLUME_DATA_DIR:-}" && -d "${VOLUME_DATA_DIR}" ]]; then
        find "${VOLUME_DATA_DIR}" -maxdepth 3 -mindepth 1 -print 2>/dev/null \
            | while IFS= read -r path; do printf '%s\n' "${path#${VOLUME_DATA_DIR}/}"; done \
            | sort | head -200 || true
    elif [[ -d "${DATA_DIR}" ]]; then
        find "${DATA_DIR}" -maxdepth 2 -mindepth 1 -print 2>/dev/null \
            | while IFS= read -r path; do printf '%s\n' "${path#${DATA_DIR}/}"; done \
            | sort | head -200 || true
    fi
}

function assert_no_pgdata_at_volume_root() {
    if [[ -z "${VOLUME_DATA_DIR:-}" || "${VOLUME_DATA_DIR}" == "${DATA_DIR}" || ! -d "${VOLUME_DATA_DIR}" ]]; then
        return
    fi

    local misplaced=()
    for path in PG_VERSION base global pg_wal; do
        if [[ -e "${VOLUME_DATA_DIR}/${path}" ]]; then
            misplaced+=("${path}")
        fi
    done

    if [[ ${#misplaced[@]} -gt 0 ]]; then
        echo "ERROR: PostgreSQL data files were found at volume root ${VOLUME_DATA_DIR}: ${misplaced[*]}" >&2
        echo "ERROR: restore payload must live under ${DATA_DIR}" >&2
        log_restore_layout >&2
        exit 1
    fi
}

function assert_pgdata_restored() {
    local missing=()
    for path in PG_VERSION base global pg_wal; do
        if [[ ! -e "${DATA_DIR}/${path}" ]]; then
            missing+=("${path}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: invalid PostgreSQL data directory after pg-basebackup restore: ${DATA_DIR}" >&2
        echo "ERROR: missing required entries: ${missing[*]}" >&2
        log_restore_layout >&2
        exit 1
    fi

    assert_no_pgdata_at_volume_root
}

function save_backup_end_lsn() {
    local backup_end_lsn=""

    # PG13+: backup_manifest contains the exact End-LSN in JSON format.
    local manifest="${DATA_DIR}/backup_manifest"
    if [[ -f "${manifest}" ]]; then
        echo "find with backup_manifest" >> "${DATA_DIR}/.backup_log"
        backup_end_lsn=$(grep -o '"End-LSN": *"[^"]*"' "${manifest}" | awk -F'"' '{print $4}')
        if [[ -n "${backup_end_lsn}" ]]; then
            echo "found backup_end_lsn: ${backup_end_lsn} from backup_manifest" >> "${DATA_DIR}/.backup_log"
        fi
    fi

    # Fallback for PG12 and older: scan WAL files with pg_waldump.
    if [[ -z "${backup_end_lsn}" ]]; then
        local wal_dir="${DATA_DIR}/pg_wal"
        echo "find with pg_wal" >> "${DATA_DIR}/.backup_log"
        for wal in $(ls -t "${wal_dir}" 2>/dev/null | grep -E '^[0-9A-F]{24}$'); do
            local wal_path="${wal_dir}/${wal}"
            # pg_waldump may exit non-zero when it hits the end of a partial WAL file,
            # which is normal for the last WAL segment in a backup.
            # so we check whether any valid records were parsed instead of relying on exit code.
            local last_record
            last_record=$(pg_waldump "${wal_path}" 2>/dev/null | tail -1 || true)
            if [[ -n "${last_record}" ]]; then
                backup_end_lsn=$(echo "${last_record}" | awk '{print $10}' | tr -d ',')
                echo "found backup_end_lsn: ${backup_end_lsn} in wal file: ${wal_path}" >> "${DATA_DIR}/.backup_log"
                break
            else
                echo "skipping invalid wal file: ${wal_path}" >> "${DATA_DIR}/.backup_log"
            fi
        done
    fi

    if [[ -n "${backup_end_lsn}" ]]; then
        echo "${backup_end_lsn}" > "${DATA_DIR}/.backup_end_lsn"
    else
        echo "warning: could not extract backup_end_lsn" >> "${DATA_DIR}/.backup_log"
    fi
}

function configure_restore_script_dir() {
    if [[ -z "${RESTORE_SCRIPT_DIR:-}" ]]; then
        if [[ -n "${VOLUME_DATA_DIR:-}" ]]; then
            RESTORE_SCRIPT_DIR="${VOLUME_DATA_DIR}/kb_restore"
        else
            RESTORE_SCRIPT_DIR="$(dirname "$(dirname "${DATA_DIR}")")/kb_restore"
        fi
    fi
    RESTORE_SCRIPT_DIR="${RESTORE_SCRIPT_DIR%/}"
}

function write_restore_hook() {
    configure_restore_script_dir
    mkdir -p "${RESTORE_SCRIPT_DIR}"
    chmod 777 "${RESTORE_SCRIPT_DIR}"
    touch "${RESTORE_SCRIPT_DIR}/kb_restore.signal"

    cat > "${RESTORE_SCRIPT_DIR}/kb_restore.sh" <<EOF
#!/bin/bash
set -e
set -o pipefail

DATA_DIR="${DATA_DIR}"
RESTORE_SCRIPT_DIR="${RESTORE_SCRIPT_DIR}"
HANDOFF_MARKER=".kb_restore_handoff"

function verify_pgdata_complete() {
    local root_dir="\$1"
    missing=()
    for path in PG_VERSION base global pg_wal; do
        if [[ ! -e "\${root_dir}/\${path}" ]]; then
            missing+=("\${path}")
        fi
    done

    if [[ \${#missing[@]} -gt 0 ]]; then
        echo "ERROR: restored PostgreSQL data directory is incomplete: \${root_dir}" >&2
        echo "ERROR: missing required entries: \${missing[*]}" >&2
        exit 1
    fi
}

IS_REPLICA=false
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        --replica)
            IS_REPLICA=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [[ "\${IS_REPLICA}" == "true" ]]; then
    echo "Replica creation detected. Patroni will use basebackup from primary."
    rm -rf "\${DATA_DIR}.old"
    rm -f "\${RESTORE_SCRIPT_DIR}/kb_restore.signal"
    exit 1
fi

if [[ ! -d "\${DATA_DIR}.old" ]]; then
    if [[ -f "\${DATA_DIR}/\${HANDOFF_MARKER}" ]]; then
        verify_pgdata_complete "\${DATA_DIR}"
        sync
        echo "Basebackup restore handoff already committed at \${DATA_DIR}"
        rm -f "\${RESTORE_SCRIPT_DIR}/kb_restore.signal"
        rm -f "\${DATA_DIR}/\${HANDOFF_MARKER}" || true
        exit 0
    fi

    if [[ -d "\${DATA_DIR}" ]] && [[ -n "\$(find "\${DATA_DIR}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        echo "ERROR: PostgreSQL data directory is non-empty but restore handoff marker is absent: \${DATA_DIR}" >&2
        exit 1
    fi

    echo "ERROR: restored PostgreSQL data handoff directory is missing: \${DATA_DIR}.old" >&2
    exit 1
fi

if [[ -d "\${DATA_DIR}" ]] && [[ -n "\$(find "\${DATA_DIR}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    echo "ERROR: PostgreSQL data directory is not empty before restore handoff: \${DATA_DIR}" >&2
    exit 1
fi

verify_pgdata_complete "\${DATA_DIR}.old"

rm -f "\${DATA_DIR}.old/standby.signal" "\${DATA_DIR}.old/recovery.signal"
touch "\${DATA_DIR}.old/\${HANDOFF_MARKER}"

if [[ "\$(id -u)" == "0" ]]; then
    chown -R postgres:postgres "\${DATA_DIR}.old" "\${RESTORE_SCRIPT_DIR}" 2>/dev/null \
        || chown -R postgres "\${DATA_DIR}.old" "\${RESTORE_SCRIPT_DIR}"
fi
chmod 00700 "\${DATA_DIR}.old"

sync
echo "Basebackup restored data accepted at \${DATA_DIR}"
rm -rf "\${DATA_DIR}"
mv "\${DATA_DIR}.old" "\${DATA_DIR}"
sync
rm -f "\${RESTORE_SCRIPT_DIR}/kb_restore.signal"
rm -f "\${DATA_DIR}/\${HANDOFF_MARKER}" || true
EOF
    chmod +x "${RESTORE_SCRIPT_DIR}/kb_restore.sh"
}

function finish_restore() {
    assert_pgdata_restored
    save_backup_end_lsn
    # PITR chain hand-off: when a restore timestamp is set, the archive-wal
    # Continuous prepareData (postgresql-pitr-restore.sh) runs next and
    # expects the base data to still live in DATA_DIR. Staging into
    # DATA_DIR.old and arming the kb_restore hook/signal here would make
    # that script fail on an empty pg_wal and leak a signal its legacy hook
    # cannot clear. Mirror wal-g-restore.sh: leave the data in place and
    # let the Continuous stage own recovery configuration.
    if [[ -n "${DP_RESTORE_TIMESTAMP:-}${DP_RESTORE_TIME:-}" ]]; then
        sync
        echo "done!";
        exit 0
    fi
    write_restore_hook
    rm -rf "${DATA_DIR}.old"
    mv "${DATA_DIR}" "${DATA_DIR}.old"
    mkdir -p "${DATA_DIR}"
    sync
    echo "done!";
    exit 0
}

validate_data_dir_contract
mkdir -p "${DATA_DIR}";

if [ $(remote_file_exists "${DP_BACKUP_NAME}.tar.zst") == "true" ]; then
  datasafed pull -d zstd-fastest "${DP_BACKUP_NAME}.tar.zst" - | tar -xvf - -C "${DATA_DIR}/"
  finish_restore
fi

# for compatibility
if [ $(remote_file_exists "${DP_BACKUP_NAME}.tar.gz") == "true" ]; then
  datasafed pull "${DP_BACKUP_NAME}.tar.gz" - | gunzip | tar -xvf - -C "${DATA_DIR}/"
  finish_restore
fi

# NOTE: restore from an old version backup, will be removed in 0.8
restored_base_archive=false
if [ $(remote_file_exists "base.tar.gz") == "true" ]; then
  datasafed pull "base.tar.gz" - | tar -xzvf - -C "${DATA_DIR}/"
  restored_base_archive=true
elif [ $(remote_file_exists "base.tar") == "true" ]; then
  datasafed pull "base.tar" - | tar -xvf - -C "${DATA_DIR}/"
  restored_base_archive=true
fi
if [ $(remote_file_exists "pg_wal.tar.gz") == "true" ]; then
  mkdir -p "${DATA_DIR}/pg_wal"
  datasafed pull "pg_wal.tar.gz" - | tar -xzvf - -C "${DATA_DIR}/pg_wal/"
elif [ $(remote_file_exists "pg_wal.tar") == "true" ]; then
  mkdir -p "${DATA_DIR}/pg_wal"
  datasafed pull "pg_wal.tar" - | tar -xvf - -C "${DATA_DIR}/pg_wal/"
fi
if [[ "${restored_base_archive}" != "true" ]]; then
  echo "ERROR: no supported pg-basebackup artifact found for ${DP_BACKUP_NAME}" >&2
  echo "ERROR: expected ${DP_BACKUP_NAME}.tar.zst, ${DP_BACKUP_NAME}.tar.gz, base.tar.gz, or base.tar" >&2
  exit 1
fi
finish_restore
