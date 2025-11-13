#!/usr/bin/env bash

set +x
set -o errexit


function info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

info "Start to leave FE member"

leader_host=""
leave_member_host=""
leave_member_port=""
leave_role=""
# always use 0 pod FQDN as helper_endpoints
helper_endpoints=$(echo "$POD_FQDN_LIST" | cut -d, -f1)
helper_pod_name=$(echo "$helper_endpoints" | cut -d: -f1 | cut -d. -f1)
candidate_names=""


# root@x-fe-0:/opt/starrocks#  mysql -h 127.0.0.1 -P 9030 -e "show frontends"
## +-----------------------------------------+------------------------------------------------------+-------------+----------+-----------+---------+--------------------+----------+----------+-----------+------+-------+-------------------+---------------------+---------------------+----------+--------+-----------------------------+------------------+
# | Name                                    | Host                                                 | EditLogPort | HttpPort | QueryPort | RpcPort | ArrowFlightSqlPort | Role     | IsMaster | ClusterId | Join | Alive | ReplayedJournalId | LastStartTime       | LastHeartbeat       | IsHelper | ErrMsg | Version                     | CurrentConnected |
# +-----------------------------------------+------------------------------------------------------+-------------+----------+-----------+---------+--------------------+----------+----------+-----------+------+-------+-------------------+---------------------+---------------------+----------+--------+-----------------------------+------------------+
# | fe_61708f2c_e1ea_4a21_8367_ea6d7103f065 | test-fe-2.test-fe-headless.default.svc.cluster.local | 9010        | 8030     | 9030      | 9020    | -1                 | FOLLOWER | false    | 606612320 | true | true  | 57                | 2025-09-25 15:28:02 | 2025-09-25 15:31:03 | true     |        | doris-2.1.6-rc04-653e315ba5 | No               |
# | fe_6ced9e5e_6a36_4b2d_83e6_e2b22b100123 | test-fe-0.test-fe-headless.default.svc.cluster.local | 9010        | 8030     | 9030      | 9020    | -1                 | FOLLOWER | true     | 606612320 | true | true  | 58                | 2025-09-25 15:27:12 | 2025-09-25 15:31:03 | true     |        | doris-2.1.6-rc04-653e315ba5 | Yes              |
# | fe_8caab8a5_a581_40ae_b9ce_934d9e135e32 | test-fe-1.test-fe-headless.default.svc.cluster.local | 9010        | 8030     | 9030      | 9020    | -1                 | FOLLOWER | false    | 606612320 | true | true  | 57                | 2025-09-25 15:27:34 | 2025-09-25 15:31:03 | true     |        | doris-2.1.6-rc04-653e315ba5 | No               |
# +-----------------------------------------+------------------------------------------------------+-------------+----------+-----------+---------+--------------------+----------+----------+-----------+------+-------+-------------------+---------------------+---------------------+----------+--------+-----------------------------+------------------+

function show_frontends() {
    local retry_count=0
    local max_retries=20
    local retry_interval=6
    while (( retry_count < max_retries )); do
        if mysql -N -B -h "${FE_DISCOVERY_ADDR}" -P 9030 -u"${DORIS_USER}" -p"${DORIS_PASSWORD}" -e "show frontends"; then
            return 0
        fi
        retry_count=$((retry_count + 1))
        info "Failed to execute 'show frontends', retrying in ${retry_interval} seconds... (${retry_count}/${max_retries})" >&2
        sleep ${retry_interval}
    done
    info "Failed to execute 'show frontends' after ${max_retries} retries." >&2
    exit 1
}

function switch_leader() {
    info "switch leader from ${leader_host} to ${candidate_names}, address:${helper_endpoints}"
    java -jar /opt/apache-doris/fe/lib/je-18.3.14-doris-SNAPSHOT.jar DbGroupAdmin -helperHosts "${helper_endpoints}" -groupName PALO_JOURNAL_GROUP -transferMaster -force "${candidate_names}" 5000
}

function wait_for_leader_switched() {
    until [[ $(show_frontends | awk '$9 == "true" {print $2}') != ${KB_LEAVE_MEMBER_POD_NAME}* ]]; do
        sleep 5
        info "waiting for leader to be switched"
    done
}

info "KB_LEAVE_MEMBER_POD_NAME: ${KB_LEAVE_MEMBER_POD_NAME}"
output=$(show_frontends)
info "frontends:"
info "${output}"

# execute a mysql command and iterate the output line by line
while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    ip=$(echo "$line" | awk '{print $2}')
    edit_log_port=$(echo "$line" | awk '{print $3}')
    role=$(echo "$line" | awk '{print $8}')
    is_master=$(echo "$line" | awk '{print $9}')
    if [[ ${ip} == ${KB_LEAVE_MEMBER_POD_NAME}* ]]; then
        leave_member_host=${ip}
        leave_member_port=${edit_log_port}
        leave_role=${role}
    fi
    if [ "${is_master}" == "true" ]; then
        leader_host=${ip}
    fi

    if [[ ${ip} == "${helper_endpoints}" ]]; then
        candidate_names=${name}
        helper_endpoints=${ip}:${edit_log_port}
    fi
done <<< "$output"

info "leave member: ${leave_member_host}:${leave_member_port}"
info "leave role: ${leave_role}"
info "leader: ${leader_host}"
info "helper hosts: ${helper_endpoints}"
info "candidate hosts: ${candidate_names}"

if [ -z "${leave_member_host}" ] || [ -z "${leave_member_port}" ]; then
    info "leave member ${KB_LEAVE_MEMBER_POD_NAME} not found, may be removed already"
    exit 0
fi

if [[ ${KB_AGENT_POD_NAME} != ${helper_pod_name} ]]; then
    switch_leader
    wait_for_leader_switched
fi

mysql -h "${leader_host}" -u"${DORIS_USER}" -p"${DORIS_PASSWORD}" -P 9030 -e "alter system drop ${leave_role} '${leave_member_host}:${leave_member_port}';"

info "leave member ${leave_member_host}:${leave_member_port} success"
