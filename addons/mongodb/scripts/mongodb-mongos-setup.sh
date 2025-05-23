#!/bin/bash

# {{- $mongodb_root := getVolumePathByName ( index $.podSpec.containers 0 ) "data" }}
# {{- $mongodb_port_info := getPortByName ( index $.podSpec.containers 0 ) "mongos" }}

# # require port
# {{- $mongodb_port := 27017 }}
# {{- if $mongodb_port_info }}
# {{- $mongodb_port = $mongodb_port_info.containerPort }}
# {{- end }}

# PORT={{ $mongodb_port }}
# MONGODB_ROOT={{ $mongodb_root }}
# mkdir -p $MONGODB_ROOT/db
# mkdir -p $MONGODB_ROOT/logs
# mkdir -p $MONGODB_ROOT/tmp

# Check if the pod is the first member of the replica set
# check_if_first_member() {
#     if [[ "${KB_POD_NAME: -1}" != "0" ]]; then
#         echo "INFO: This pod $KB_POD_NAME is not the first member of the replica set, exiting."
#         return 1
#     fi
#     return 0
# }

generate_endpoints() {
    local fqdns=$1
    local port=$2

    if [ -z "$fqdns" ]; then
        echo "ERROR: No FQDNs provided for config server endpoints." >&2
        exit 1
    fi

    IFS=',' read -ra fqdn_array <<< "$fqdns"
    local endpoints=()

    for fqdn in "${fqdn_array[@]}"; do
        trimmed_fqdn=$(echo "$fqdn" | xargs)
        if [[ -n "$trimmed_fqdn" ]]; then
            endpoints+=("${trimmed_fqdn}:${port}")
        fi
    done

    IFS=','; echo "${endpoints[*]}"
}

cfg_server_endpoints="$(generate_endpoints "$CFG_SERVER_POD_FQDN_LIST" "$CFG_SERVER_INTERNAL_PORT")"

# PORT_FOR_PREPARE=27027
# CLIENT=`which mongosh>/dev/null&&echo mongosh||echo mongo`

# if check_if_first_member; then
#     mongos --bind_ip_all --port $PORT_FOR_PREPARE --configdb $CFG_SERVER_REPLICA_SET_NAME/$cfg_server_endpoints --config /etc/mongodb/mongos.conf --pidfilepath $MONGODB_ROOT/tmp/mongodb.pid&
#     until $CLIENT --quiet --port $PORT_FOR_PREPARE --eval "print('prepare root account')"; do sleep 1; done
#     PID=`cat $MONGODB_ROOT/tmp/mongodb.pid`

#     # Check if balancer is enabled
#     echo "INFO: Checking if balancer is enabled..."
#     balancer_state=$($CLIENT --quiet --port $PORT_FOR_PREPARE --eval "sh.getBalancerState()")
#     if [[ "$balancer_state" == "false" ]]; then
#         echo "INFO: Balancer is disabled, enabling it now..."
#         $CLIENT --quiet --port $PORT_FOR_PREPARE --eval "sh.startBalancer()"
#     else
#         echo "INFO: Balancer is already enabled"
#     fi

#     # MongoDB connection and user creation command
#     echo "INFO: Creating root user..."
#     $CLIENT --quiet --port $PORT_FOR_PREPARE --eval "
#     try {
#         // Check if user already exists
#         if (db.getSiblingDB('admin').getUser('$MONGODB_ROOT_USER')) {
#             print('[SKIPPED] User already exists');
#             quit(0);
#         }

#         // Create root user with full privileges
#         db.getSiblingDB('admin').createUser({
#             user: '$MONGODB_ROOT_USER',
#             pwd: '$MONGODB_ROOT_PASSWORD',
#             roles: [{ role: 'root', db: 'admin' }]
#         });
        
#         print('[SUCCESS] Root user created');
#     } catch (e) {
#         print('[ERROR] ' + e.message);
#         quit(1);
#     }"

#     kill $PID
#     wait $PID
#     echo "INFO: Successfully provisioned account."
#     echo "User: $MONGODB_ROOT_USER , Password: $MONGODB_ROOT_PASSWORD."
# fi

exec mongos --bind_ip_all --port $KB_SERVICE_PORT --configdb $CFG_SERVER_REPLICA_SET_NAME/$cfg_server_endpoints --config /etc/mongodb/mongos.conf