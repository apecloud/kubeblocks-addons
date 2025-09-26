#!/bin/bash

fe_role_probe()
{

# SHOW FRONTENDS output like:
# 
# +-----------------------------------------+------------------------------------------------------+-------------+----------+-----------+---------+--------------------+----------+----------+-----------+------+-------+-------------------+---------------------+---------------------+----------+--------+-----------------------------+------------------+
# | Name                                    | Host                                                 | EditLogPort | HttpPort | QueryPort | RpcPort | ArrowFlightSqlPort | Role     | IsMaster | ClusterId | Join | Alive | ReplayedJournalId | LastStartTime       | LastHeartbeat       | IsHelper | ErrMsg | Version                     | CurrentConnected |
# +-----------------------------------------+------------------------------------------------------+-------------+----------+-----------+---------+--------------------+----------+----------+-----------+------+-------+-------------------+---------------------+---------------------+----------+--------+-----------------------------+------------------+
# | fe_61708f2c_e1ea_4a21_8367_ea6d7103f065 | test-fe-2.test-fe-headless.default.svc.cluster.local | 9010        | 8030     | 9030      | 9020    | -1                 | FOLLOWER | false    | 606612320 | true | true  | 57                | 2025-09-25 15:28:02 | 2025-09-25 15:31:03 | true     |        | doris-2.1.6-rc04-653e315ba5 | No               |
# | fe_6ced9e5e_6a36_4b2d_83e6_e2b22b100123 | test-fe-0.test-fe-headless.default.svc.cluster.local | 9010        | 8030     | 9030      | 9020    | -1                 | FOLLOWER | true     | 606612320 | true | true  | 58                | 2025-09-25 15:27:12 | 2025-09-25 15:31:03 | true     |        | doris-2.1.6-rc04-653e315ba5 | Yes              |
# | fe_8caab8a5_a581_40ae_b9ce_934d9e135e32 | test-fe-1.test-fe-headless.default.svc.cluster.local | 9010        | 8030     | 9030      | 9020    | -1                 | FOLLOWER | false    | 606612320 | true | true  | 57                | 2025-09-25 15:27:34 | 2025-09-25 15:31:03 | true     |        | doris-2.1.6-rc04-653e315ba5 | No               |
# +-----------------------------------------+------------------------------------------------------+-------------+----------+-----------+---------+--------------------+----------+----------+-----------+------+-------+-------------------+---------------------+---------------------+----------+--------+-----------------------------+------------------+

    SELF_FE_FQDN="$(hostname -f)"
    probe_output=$(mysql -h "${FE_DISCOVERY_ADDR}" -P "${FE_QUERY_PORT}" -u "${DORIS_USER}" -p"${DORIS_PASSWORD}" -e "SHOW FRONTENDS" 2>/dev/null || true)
    is_master_value=$(echo "${probe_output}" | grep -w "${SELF_FE_FQDN}" | awk '{print $9}' || true)
    role_value=$(echo "${probe_output}" | grep -w "${SELF_FE_FQDN}" | awk '{print $8}' || true)
    if [[ "x${role_value}" != "xFOLLOWER" ]]; then
        echo "${role_value}"
        return 0
    fi

    if [[ "x${is_master_value}" == "x" ]]; then
        return 1
    fi

    if [[ "x${is_master_value}" == "xtrue" ]]; then
        echo "master"
        return 0
    fi

    if [[ "x${is_master_value}" == "xfalse" ]]; then
        echo "follower"
        return 0
    fi

}

fe_role_probe
