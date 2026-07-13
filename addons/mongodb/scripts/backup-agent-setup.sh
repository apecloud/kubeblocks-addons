#!/bin/bash
# shellcheck disable=SC2086

export PATH=$PBM_DATA_MOUNT_POINT/tmp/bin:$PATH

exec pbm-agent-entrypoint
