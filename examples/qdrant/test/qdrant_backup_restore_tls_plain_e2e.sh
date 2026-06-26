#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=qdrant_e2e_lib.sh
. "${SCRIPT_DIR}/qdrant_e2e_lib.sh"

run_qdrant_backup_restore_case "tls-no-auth" "true" "none"
