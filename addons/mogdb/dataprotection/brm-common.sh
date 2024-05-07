# brm variables setting
: ${BRM_CONFIG:=/etc/brm.yaml}
: ${BACKUP_ROOTDIR:=/backupdata}
: ${BACKUP_DIR:=mogdb}
: ${PGDATA:=/var/lib/mogdb/data}
: ${LAST_INFO:=last_info.log}
: ${ARCHIVE_DIR:=/var/lib/mogdb/archives}


function brm_backup_dir() {
    echo "${BACKUP_ROOTDIR}/${BACKUP_DIR}"
}

function brm_instance_backup_dir() {
    echo $(brm_backup_dir)/backups/${KB_CLUSTER_NAME}
}

function brm_instance_wal_dir() {
    echo $(brm_backup_dir)/wal/${KB_CLUSTER_NAME}
}

function init_brm_required_vars() {
    BRM_BACKUP_DIR=$(brm_backup_dir)
    BRM_INST_BACKUP_DIR=$(brm_instance_backup_dir)
    BRM_INST_WAL_DIR=$(brm_instance_wal_dir)
}

function brm_cleanup_instance() {
    local inst="$1"

    if [ -n "$inst" ]; then
        rm -rf $(brm_instance_backup_dir)
        rm -rf $(brm_instance_wal_dir)
    fi
}

function is_first_backup() {
    # TODO: simple judgment currently, enhance this logic in the future
    local inst_backup_dir=$(brm_instance_backup_dir)

    for dir in $(ls $inst_backup_dir); do
        if [ -d "$inst_backup_dir/$dir" ] && [[ "$dir" =~ [A-Z0-9]+ ]]; then
            return 1
        fi
    done

    return 0
}

function setup_brm_configure() {
    which yq >/dev/null || apt_get_install_package yq

    local brm_dir=$(home_directory omm)/brm
    test -d ${brm_dir} || {
        echo "Making brm directory.."
        mkdir -p ${brm_dir}
        chown -R omm:omm ${brm_dir}
    }

    yq -i ".backup_home = \"$(brm_backup_dir)\"" ${BRM_CONFIG}
    yq -i ".log_file = \"${brm_dir}/brm.log\"" ${BRM_CONFIG}
    yq -i ".lock_directory = \"/var/run\"" ${BRM_CONFIG}
}

function brm_add_server() {
    local inst_backup_dir=$(brm_instance_backup_dir)

    local cmd=(gosu omm brm)
    if [ ! -e "$inst_backup_dir" ]; then
        cmd+=(add-server)
    else
        cmd+=(set-server)
    fi

    ${cmd[@]} \
    -i ${KB_CLUSTER_NAME} \
    -D ${PGDATA} \
    --pghost=${DP_DB_HOST} \
    --pguser=${DP_DB_USER}  \
    --pgpassword=\'${DP_DB_PASSWORD}\' \
    --remote-user=omm --remote-host=${DP_DB_HOST} \
    -p ${PGPORT:-26000}
}


function brm_set_server_wal() {
    brm set-server -i ${KB_CLUSTER_NAME} --archive-dir=${ARCHIVE_DIR}
}


function brm_analysis_log() {
    # last_info.log
    local last_line=$(tail -n 1 ${BRM_INST_BACKUP_DIR}/${LAST_INFO})

    if [[ "$last_line" =~ "Backup "([A-Z0-9]+)" completed" ]]; then
        local backup_id=${BASH_REMATCH[1]}
    fi

    echo "{\"backup_id\":\"$backup_id\"}"
}

function brm_backup_info() {
    local backup_id="$1"
    local cmd=(brm show-backup)

    if [ -n "$backup_id" ]; then
        cmd+=(-b $backup_id -i ${KB_CLUSTER_NAME} -f JSON)
    fi

    local output=$(${cmd[@]})

    if [[ $output =~ \[.*\] ]]; then
        echo ${BASH_REMATCH[0]}
    else
        echo "[]"
    fi
}