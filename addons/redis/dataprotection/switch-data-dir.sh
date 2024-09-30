if [ -n "$DP_RESTORE_KEY_PATTERNS" ]; then
    DP_log "DP_RESTORE_KEY_PATTERNS is set, switching data directory to ${DATA_DIR}/.restore_keys"
    DATA_DIR="${DATA_DIR}/.restore_keys"
fi
