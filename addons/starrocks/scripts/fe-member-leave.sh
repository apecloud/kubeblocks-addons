#!/usr/bin/env bash

set -x
set -o errexit

leader_host=""
leave_member_host=""
leave_member_port=""
helper_endpoints=""
candidate_names=""

function info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# root@x-fe-0:/opt/starrocks#  mysql -h 127.0.0.1 -P 9030 -e "show frontends"
# +-------------------------------------------------------------------------------+------------------------------------------------------------+-------------+----------+-----------+---------+----------+------------+------+-------+-------------------+---------------------+----------+--------+---------------------+---------------+
# | Name                                                                          | IP                                                         | EditLogPort | HttpPort | QueryPort | RpcPort | Role     | ClusterId  | Join | Alive | ReplayedJournalId | LastHeartbeat       | IsHelper | ErrMsg | StartTime           | Version       |
# +-------------------------------------------------------------------------------+------------------------------------------------------------+-------------+----------+-----------+---------+----------+------------+------+-------+-------------------+---------------------+----------+--------+---------------------+---------------+
# | x-fe-1.x-fe-headless.kubeblocks-cloud-ns.svc.cluster.local_9010_1717662978660 | x-fe-1.x-fe-headless.kubeblocks-cloud-ns.svc.cluster.local | 9010        | 8030     | 9030      | 9020    | FOLLOWER | 1847720530 | true | true  | 179               | 2024-06-06 16:42:30 | true     |        | 2024-06-06 16:36:30 | 3.2.2-269e832 |
# | x-fe-0.x-fe-headless.kubeblocks-cloud-ns.svc.cluster.local_9010_1717662806744 | x-fe-0.x-fe-headless.kubeblocks-cloud-ns.svc.cluster.local | 9010        | 8030     | 9030      | 9020    | LEADER   | 1847720530 | true | true  | 180               | 2024-06-06 16:42:30 | true     |        | 2024-06-06 16:33:47 | 3.2.2-269e832 |
# | x-fe-2.x-fe-headless.kubeblocks-cloud-ns.svc.cluster.local_9010_1717662978644 | x-fe-2.x-fe-headless.kubeblocks-cloud-ns.svc.cluster.local | 9010        | 8030     | 9030      | 9020    | FOLLOWER | 1847720530 | true | true  | 179               | 2024-06-06 16:42:30 | true     |        | 2024-06-06 16:36:41 | 3.2.2-269e832 |
# +-------------------------------------------------------------------------------+------------------------------------------------------------+-------------+----------+-----------+---------+----------+------------+------+-------+-------------------+---------------------+----------+--------+---------------------+---------------+
function show_frontends() {
    mysql -N -B -h "${FE_DISCOVERY_ADDR}" -P 9030 -u"${STARROCKS_USER}" -p"${STARROCKS_PASSWORD}" -e "show frontends"
}

function switch_leader() {
    java -jar /opt/starrocks/fe/lib/starrocks-bdb-je*.jar DbGroupAdmin -helperHosts "${helper_endpoints}" -groupName PALO_JOURNAL_GROUP -transferMaster -force "${candidate_names}" 5000
}

function wait_for_leader_switched() {
    until [[ $(show_frontends | grep 'LEADER' | awk '{print $2}') != ${KB_LEAVE_MEMBER_POD_NAME}* ]]; do
        sleep 5
        info "waiting for leader to be switched"
    done
}

# execute a mysql command and iterate the output line by line
output=$(show_frontends)
while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    ip=$(echo "$line" | awk '{print $2}')
    edit_log_port=$(echo "$line" | awk '{print $3}')
    role=$(echo "$line" | awk '{print $7}')
    is_leaving=False
    if [[ ${ip} == ${KB_LEAVE_MEMBER_POD_NAME}* ]]; then
        is_leaving=True
        leave_member_host=${ip}
        leave_member_port=${edit_log_port}
    fi
    if [ "${role}" == "LEADER" ]; then
        leader_host=${ip}
    fi
    if [ "${is_leaving}" == "False" ]; then
        if [ -n "${helper_endpoints}" ]; then
            helper_endpoints=${helper_endpoints},${ip}:${edit_log_port}
            candidate_names=${candidate_names},${name}
        else
            helper_endpoints=${ip}:${edit_log_port}
            candidate_names=${name}
        fi
    fi
done <<< "$output"

info "leave member: ${leave_member_host}:${leave_member_port}"
info "leader: ${leader_host}"
info "helper hosts: ${helper_endpoints}"
info "candidate hosts: ${candidate_names}"

if [ -z "${leave_member_host}" ] || [ -z "${leave_member_port}" ]; then
    info "leave member ${KB_LEAVE_MEMBER_POD_NAME} not found, may be removed already"
    exit 0
fi

# The leader will exit if lost it's leader role
if [[ ${leader_host} == ${KB_LEAVE_MEMBER_POD_NAME}* ]]; then
    switch_leader
    wait_for_leader_switched
fi

mysql -h "${leader_host}" -P 9030 -e "alter system drop follower '${leave_member_host}:${leave_member_port}';"