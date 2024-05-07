#set -e
#set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export PGPASSWORD=${DP_DB_PASSWORD}

trap handle_exit EXIT

START_TIME=`get_current_time`
BACKUP_TMPDIR="/tmp"

function brm_backup() {
    gosu omm brm backup -i ${KB_CLUSTER_NAME} --debug=info | tee $(brm_instance_backup_dir)/${LAST_INFO}
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
brm_add_server

# backup using brm
echo "Backuping.."
brm_backup

# stat and save the backup information
stat_and_save_backup_info $START_TIME

# temporarily add for test
# TODO: remove it in the future
# sleep infinity