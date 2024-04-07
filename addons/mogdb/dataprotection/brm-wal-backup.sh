# brm backup-wal -i test --debug=info

START_TIME=`get_current_time`

function brm_ptrack_backup() {
    brm backup-wal -i ${KB_CLUSTER_NAME} --debug=info | tee ${BRM_INST_WAL_DIR}/${LAST_INFO}
}


function save_backup_status() {
    echo
}


echo "Init brm required vars.."
init_brm_required_vars

# setup brm configuration
echo "Setuping brm configuration.."
setup_brm_configure

echo "Configure ssh.."
setup_ssh_configure

# add brm server
echo "Adding brm server.."
brm_set_server_wal

# trap term signal
trap "echo 'Terminating...' && sync && exit 0" TERM
DP_log "start to archive wal logs"
while true; do
    brm_ptrack_backup

    save_backup_status

    sleep ${LOG_ARCHIVE_SECONDS}

    # temporarily add for test
    # TODO: remove it in the future
    sleep infinity
done

