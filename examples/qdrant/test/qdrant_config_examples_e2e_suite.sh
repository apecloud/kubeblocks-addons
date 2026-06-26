#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/qdrant_backup_restore_plain_e2e.sh"
"${SCRIPT_DIR}/qdrant_backup_restore_config_api_key_e2e.sh"
"${SCRIPT_DIR}/qdrant_backup_restore_env_api_key_e2e.sh"
"${SCRIPT_DIR}/qdrant_backup_restore_tls_plain_e2e.sh"
"${SCRIPT_DIR}/qdrant_backup_restore_tls_config_api_key_e2e.sh"
"${SCRIPT_DIR}/qdrant_backup_restore_tls_env_api_key_e2e.sh"

echo "INFO: qdrant config/examples e2e suite passed"
