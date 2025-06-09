set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_exit EXIT

cfg_server_endpoints="$(generate_endpoints "$CFG_SERVER_POD_FQDN_LIST" "$CFG_SERVER_INTERNAL_PORT")"
export PBM_MONGODB_URI="mongodb://$MONGODB_USER:$MONGODB_PASSWORD@$cfg_server_endpoints/?authSource=admin&replSetName=$CFG_SERVER_REPLICA_SET_NAME"

set_backup_config_env

