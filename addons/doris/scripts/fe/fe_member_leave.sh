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
## +-----------------------------------------+------------------------------------------------------+-------------+----------+-----------+---------+--------------------+----------+----------+-----------+------+-------+-------------------+---------------------+---------------------+----------+--------+-----------------------------+------------------+
# | Name                                    | Host                                                 | EditLogPort | HttpPort | QueryPort | RpcPort | ArrowFlightSqlPort | Role     | IsMaster | ClusterId | Join | Alive | ReplayedJournalId | LastStartTime       | LastHeartbeat       | IsHelper | ErrMsg | Version                     | CurrentConnected |
# +-----------------------------------------+------------------------------------------------------+-------------+----------+-----------+---------+--------------------+----------+----------+-----------+------+-------+-------------------+---------------------+---------------------+----------+--------+-----------------------------+------------------+
# | fe_61708f2c_e1ea_4a21_8367_ea6d7103f065 | test-fe-2.test-fe-headless.default.svc.cluster.local | 9010        | 8030     | 9030      | 9020    | -1                 | FOLLOWER | false    | 606612320 | true | true  | 57                | 2025-09-25 15:28:02 | 2025-09-25 15:31:03 | true     |        | doris-2.1.6-rc04-653e315ba5 | No               |
# | fe_6ced9e5e_6a36_4b2d_83e6_e2b22b100123 | test-fe-0.test-fe-headless.default.svc.cluster.local | 9010        | 8030     | 9030      | 9020    | -1                 | FOLLOWER | true     | 606612320 | true | true  | 58                | 2025-09-25 15:27:12 | 2025-09-25 15:31:03 | true     |        | doris-2.1.6-rc04-653e315ba5 | Yes              |
# | fe_8caab8a5_a581_40ae_b9ce_934d9e135e32 | test-fe-1.test-fe-headless.default.svc.cluster.local | 9010        | 8030     | 9030      | 9020    | -1                 | FOLLOWER | false    | 606612320 | true | true  | 57                | 2025-09-25 15:27:34 | 2025-09-25 15:31:03 | true     |        | doris-2.1.6-rc04-653e315ba5 | No               |
# +-----------------------------------------+------------------------------------------------------+-------------+----------+-----------+---------+--------------------+----------+----------+-----------+------+-------+-------------------+---------------------+---------------------+----------+--------+-----------------------------+------------------+

function show_frontends() {
    mysql -N -B -h "${FE_DISCOVERY_ADDR}" -P 9030 -u"${DORIS_USER}" -p"${DORIS_PASSWORD}" -e "show frontends"
}

function switch_leader() {
    java -jar /opt/apache-doris/fe/lib/je-18.3.14-doris-SNAPSHOT.jar DbGroupAdmin -helperHosts "${helper_endpoints}" -groupName PALO_JOURNAL_GROUP -transferMaster -force "${candidate_names}" 5000
}

function wait_for_leader_switched() {
    until [[ $(show_frontends | awk '$9 == "true" {print $2}') != ${KB_LEAVE_MEMBER_POD_NAME}* ]]; do
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
    role=$(echo "$line" | awk '{print $8}')
    is_master=$(echo "$line" | awk '{print $9}')
    is_leaving=False
    if [[ ${ip} == ${KB_LEAVE_MEMBER_POD_NAME}* ]]; then
        is_leaving=True
        leave_member_host=${ip}
        leave_member_port=${edit_log_port}
    fi
    if [ "${is_master}" == "true" ]; then
        leader_host=${ip}
    fi
    if [ "${is_leaving}" == "False" ] && [ "${role}" == "FOLLOWER" ]; then
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

mysql -h "${leader_host}" -P 9030 -e "alter system drop ${role} '${leave_member_host}:${leave_member_port}';"
