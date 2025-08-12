#!/usr/bin/env bash

function info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

DEFAULT_WAREHOUSE=default_warehouse
member=${KB_POD_NAME}.${KB_CLUSTER_COMP_NAME}-headless.${KB_NAMESPACE}.svc.cluster.local
member_heartbeat_port=9050
mysql_exec="mysql -h ${FE_DISCOVERY_ADDR} -P 9030 -u${STARROCKS_USER} -p${STARROCKS_PASSWORD}"

expect_warehouse=${WAREHOUSE_NAME}
if [ -z "${expect_warehouse}" ]; then
    expect_warehouse=${DEFAULT_WAREHOUSE}
fi

function remove_node_from_warehouse()
{
    info "remove the member ${member} from warehouse ${actual_warehouse}"
    ${mysql_exec} -e "alter system drop compute node '${member}:${member_heartbeat_port}' from warehouse ${actual_warehouse}"
}

function add_node_into_warehouse()
{
    info "add the member ${member} to warehouse ${expect_warehouse}"
    ${mysql_exec} -e "alter system add compute node '${member}:${member_heartbeat_port}' into warehouse ${expect_warehouse}"
}

function create_warehouse() {
    info "create warehouse ${expect_warehouse}"
    ${mysql_exec} -e "create warehouse if not exists ${expect_warehouse}"
}

while true; do
    curl --fail --connect-timeout 1 http://127.0.0.1:8040/api/health > /dev/null 2>&1
    if [ $? == 0 ]; then
        info "cn is ready"
        break
    fi
    sleep 1
    info "waiting for cn to be ready"
done

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
echo "${lines}" | grep WarehouseName
if [ $? != 0 ]; then
    info "warehouse is not supported, skip"
    exit 0
fi
line=$(echo "${lines}" | grep "${member}")
if [ $? == 0 ]; then
    actual_warehouse=$(echo "$line" | awk '{print $(NF-1)}')
    if [ "${actual_warehouse}" == "${expect_warehouse}" ]; then
        info "member ${member} has already in the warehouse ${expect_warehouse}, exit"
        exit 0
    fi
    remove_node_from_warehouse
fi

create_warehouse
add_node_into_warehouse