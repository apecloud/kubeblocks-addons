#!/bin/bash
# shellcheck disable=SC2086

# The sidecar container now runs syncer with the pbm-agent workload type. The
# syncer PBMAgentDPEngine starts/stops the permanent pbm-agent based on restore
# phase from the restore-coord ConfigMap.
exec /tools/syncer -- /tools/pbm-agent-entrypoint
