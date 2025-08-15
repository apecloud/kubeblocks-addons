#!/usr/bin/env bash

set -x

function info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

member=${KB_LEAVE_MEMBER_POD_NAME}.${KB_CLUSTER_COMP_NAME}-headless.${KB_NAMESPACE}.svc.cluster.local
member_heartbeat_port=9050
mysql_exec="mysql -h ${FE_DISCOVERY_ADDR} -P 9030 -u${STARROCKS_USER} -p${STARROCKS_PASSWORD}"

# mysql> show compute nodes;
# +---------------+----------------------------------------------------------------------------------------+---------------+--------+----------+----------+---------------------+---------------------+-------+----------------------+-----------------------+--------+---------------+----------+-------------------+------------+------------+---------------------------------------------------+----------------+-------------+----------+-------------------+-----------+
# | ComputeNodeId | IP                                                                                     | HeartbeatPort | BePort | HttpPort | BrpcPort | LastStartTime       | LastHeartbeat       | Alive | SystemDecommissioned | ClusterDecommissioned | ErrMsg | Version       | CpuCores | NumRunningQueries | MemUsedPct | CpuUsedPct | DataCacheMetrics                                  | HasStoragePath | StarletPort | WorkerId | WarehouseName     | TabletNum |
# +---------------+----------------------------------------------------------------------------------------+---------------+--------+----------+----------+---------------------+---------------------+-------+----------------------+-----------------------+--------+---------------+----------+-------------------+------------+------------+---------------------------------------------------+----------------+-------------+----------+-------------------+-----------+
# | 10001         | maple-b97d47b77-cn-0.maple-b97d47b77-cn-headless.kubeblocks-cloud-ns.svc.cluster.local | 9050          | 9060   | 8040     | 8060     | 2024-08-26 14:54:18 | 2024-08-26 14:56:38 | true  | false                | false                 |        | 3.3.0-19a3f66 | 1        | 0                 | 14.90 %    | 0.0 %      | Status: Normal, DiskUsage: 0B/0B, MemUsage: 0B/0B | true           | 9070        | 1        | default_warehouse | 58        |
# +---------------+----------------------------------------------------------------------------------------+---------------+--------+----------+----------+---------------------+---------------------+-------+----------------------+-----------------------+--------+---------------+----------+-------------------+------------+------------+---------------------------------------------------+----------------+-------------+----------+-------------------+-----------+
lines=$(${mysql_exec} -B -e "show compute nodes" )
if [ $? != 0 ]; then
    info "get compute nodes list failed"
    exit 1
fi

line=$(echo "${lines}" | grep "${member}")
if [ $? != 0 ]; then
    info "can not find member ${member}, exit"
    exit 0
fi

warehouse=$(echo "$line" | awk '{print $(NF-1)}')
info "remove the member ${member} from warehouse ${warehouse}"

# Try to drop compute node with warehouse syntax first (for newer versions)
drop_result=$(${mysql_exec} -e "alter system drop compute node '${member}:${member_heartbeat_port}' from warehouse ${warehouse}" 2>&1)
if [ $? != 0 ]; then
    # Check if the error is due to unsupported warehouse syntax
    if echo "$drop_result" | grep -q "Unexpected input 'from'"; then
        info "warehouse syntax not supported, trying without warehouse clause"
        # Fallback to simple syntax for older versions
        ${mysql_exec} -e "alter system drop compute node '${member}:${member_heartbeat_port}'"
        if [ $? != 0 ]; then
            info "failed to drop compute node without warehouse clause"
            exit 1
        fi
    else
        info "failed to drop compute node: $drop_result"
        exit 1
    fi
fi

info "successfully removed compute node ${member}"
