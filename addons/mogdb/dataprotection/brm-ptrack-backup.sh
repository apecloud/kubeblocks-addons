START_TIME=`get_current_time`

function brm_ptrack_backup() {
    if is_first_backup; then
        gosu omm brm backup -i ${KB_CLUSTER_NAME} --debug=info | tee $(brm_instance_backup_dir)/${LAST_INFO}
    else
        gosu omm brm backup -i ${KB_CLUSTER_NAME} -b PTRACK --debug=info | tee $(brm_instance_backup_dir)/${LAST_INFO}
    fi
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

echo "Starting ptrack backup.."
brm_ptrack_backup

# stat and save the backup information
stat_and_save_backup_info $START_TIME

# temporarily add for test
# TODO: remove it in the future
# sleep infinity