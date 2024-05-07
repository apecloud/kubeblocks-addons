#!/bin/bash
#

source /kb-scripts/setup.sh
source /kb-scripts/library.sh


HOSTNAME=$(hostname)
ORDINAL=
AGENT_PORT=6688

PHASE_BUILDING="building"
PHASE_RUNNING="running"

APT_UPDATE=false


function apt_get_install_package() {
    local pkg="$1"
    if [ "${!pkg:-}" ]; then
        echo "Apt-get install package not provide"
        exit 1
    fi

    OLD_LD_LIBRARY_PATH=${LD_LIBRARY_PATH}
    unset LD_LIBRARY_PATH

    if [ "$APT_UPDATE" == "false" ]; then
        echo "Apt-get updating..."
        apt-get update

        APT_UPDATE="true"
    fi

    # Install package
    echo "Apt-get install package $pkg..."
    apt-get install -y $pkg

    LD_LIBRARY_PATH=${OLD_LD_LIBRARY_PATH}
}


function install_requirement_package() {
    OLD_LD_LIBRARY_PATH=${LD_LIBRARY_PATH}
    unset LD_LIBRARY_PATH

    apt-get update
    echo "Installing open ssh server, client, jq etc."
    DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server \
    openssh-server \
    jq \
    expect \
    unzip

    # TODO: add this logic to image
    # install brm package
    echo "Installing brm package.."
    mkdir -p /tmp/brm
    wget http://cdn-mogdb.enmotech.com/brm/v1.0.6/brm_1.0.6_linux_amd64.zip -O /tmp/brm/brm.zip
    unzip /tmp/brm/brm.zip -d /tmp/brm
    cp /tmp/brm/brm /usr/local/bin
    cp /tmp/brm/conf/brm.yaml /etc/brm.yaml
    rm -rf /tmp/brm

    # TODO: move this logic to image
    # install yq tool

    LD_LIBRARY_PATH=${OLD_LD_LIBRARY_PATH}
}



function setup_ssh_configure() {
    if [ ! -f /etc/ssh/ssh_config ]; then
        echo "SSH client config not exist!"
        exit 1
    fi

    {
        echo "StrictHostKeyChecking no"
    } >> /etc/ssh/ssh_config

    mkdir -p /home/omm/.ssh
    cp /home/omm/ssh/id_rsa.pub /home/omm/.ssh/authorized_keys

    chown -R omm:omm /home/omm/.ssh
}

function start_ssh_service() {
    setup_ssh_configure

    mkdir -p /run/sshd
    /usr/sbin/sshd -D &
}

function notify_cluster_peers() {
    for ((i=0; i<$ORDINAL; i++)); do
        local peer_ip=$(ping ${KB_CLUSTER_COMP_NAME}-${i}.${KB_CLUSTER_COMP_NAME}-headless -c 1 | sed '1{s/[^(]*(//;s/).*//;q}')
        local key="replconninfo${ORDINAL}"
        local value="localhost=$peer_ip localport=$(($PGPORT+1)) localservice=$(($PGPORT+2)) remotehost=$KB_PODIP remoteport=$(($PGPORT+1)) remoteservice=$(($PGPORT+2))"
        local cmd=(mscli curl http://${peer_ip}:${AGENT_PORT}/api/v1/mogdb/pgconf -X PATCH -d "'{\"action\":\"reload\",\"key\":\"${key}\",\"value\":\"${value}\"}'")

        eval "${cmd[*]}"
    done
}


function get_pod_ip_list {
  # Get the headless service name
  IP_LIST=()

  # wait for up to 10 minutes for the server to be ready
  local wait_time=600
  # Get every replica's IP
  for i in $(seq 0 $(($KB_REPLICA_COUNT-1))); do
    local replica_hostname="${KB_CLUSTER_COMP_NAME}-${i}"
    local replica_ip=""
    if [ $i -ne $ORDINAL_INDEX ]; then
      echo "nslookup $replica_hostname.$SVC_NAME"
      local elapsed_time=0
      while [ $elapsed_time -lt $wait_time ]; do
        replica_ip=$(nslookup $replica_hostname.$SVC_NAME | tail -n 2 | grep -P "(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})" --only-matching)
        if [ $? -ne 0 ]; then
          echo "$replica_hostname.$SVC_NAME is not ready yet"
          sleep 10
          elapsed_time=$((elapsed_time + 10))
        else
          echo "$replica_hostname.$SVC_NAME is ready"
          echo "nslookup $replica_hostname.$SVC_NAME success, IP: $replica_ip"
          break
        fi
      done
      if [ $elapsed_time -ge $wait_time ]; then
        echo "Failed to get the IP of $replica_hostname.$SVC_NAME, exit..."
        exit 1
      fi
    else
      replica_ip=$KB_POD_IP
    fi

    IP_LIST+=("$replica_ip")
  done

  echo "get_pod_ip_list: ${IP_LIST[*]}"
  echo "rs_list: $RS_LIST"
}


function get_primary_pod_ip() {
    PRIMARY_POD_IP=
}


function set_phase() {
    local phase="$1"

    echo -e "$phase" > /tmp/phase
}


function add_server() {
    echo "add server"
    echo "IP_LIST: ${IP_LIST[*]}"

    local suffix=1
    for ((i=0; i<$KB_REPLICA_COUNT; i++)); do
        if [ $i -eq $ORDINAL_INDEX ]; then
            continue
        fi

        local cmd=(gs_guc reload -D $PGDATA -c \"replconninfo${suffix} = \'localhost=$KB_PODIP localport=$(($PGPORT+1)) localservice=$(($PGPORT+2)) remotehost=${IP_LIST[$i]} remoteport=$(($PGPORT+1)) remoteservice=$(($PGPORT+2))\'\")

        eval "${cmd[*]}"

        suffix=$(($suffix+1))
    done
}


function is_primary_ready() {
    echo
}


function wait_until_previous_pods_running() {
    echo
}


function add_peers_to_self() {
    for ((i=0; i<$ORDINAL; i++)); do
        local key="replconninfo$((i+1))"
        local peer_ip=$(ping ${KB_CLUSTER_COMP_NAME}-${i}.${KB_CLUSTER_COMP_NAME}-headless -c 1 | sed '1{s/[^(]*(//;s/).*//;q}')
        local value="'localhost=$KB_PODIP localport=$(($PGPORT+1)) localservice=$(($PGPORT+2)) remotehost=$peer_ip remoteport=$(($PGPORT+1)) remoteservice=$(($PGPORT+2))'"

        local cmd=(gs_guc reload -D $PGDATA -c \"$key = $value\")

        eval "${cmd[*]}"
    done
}


function mogdb_required_environments() {
    local path=$(add_path "$GAUSSHOME/bin")

    cat <<-EOF
GAUSSHOME="$GAUSSHOME"
PGHOST="$PGHOST"
PGPORT="$PGPORT"
PATH="$path"
EOF
}


function add_environment_to_omm() {
    mogdb_required_environments >> /etc/environment
}

echo "Setup env variables"
docker_setup_env

if [ "$(id -u)" = '0' ]; then
    # install_requirement_package

    echo "Start sshd service..."
    start_ssh_service

    # then restart script as postgres user
    echo "Copy config file from cm"
    cp /home/omm/conf/* /tmp/
    chmod 777 /tmp/postgresql.conf /tmp/pg_hba.conf

    echo "Add required envs to omm"
    add_environment_to_omm

    echo "Create required directories for mogdb"
    docker_create_db_directories

    echo "Script run as root, will replay as omm"
    exec gosu omm "$BASH_SOURCE" "$@"
fi

# add mogdb tools directory to PATH
export PATH="/mogdb_tools:$PATH"

if [[ ! "$HOSTNAME" =~ -([0-9]+)$ ]]; then
    echo "Hostname $HOSTNAME is not valid"
    exit 1
fi
ORDINAL=${BASH_REMATCH[1]}

if [[ $ORDINAL -eq 0 ]]; then
  SERVER_MODE="primary"
else
  SERVER_MODE="standby"
fi
echo "Mogdb role is $SERVER_MODE"

if [ "$1" != 'mogdb' ]; then
    set -- mogdb -M $SERVER_MODE "$@"
fi


if [ -z "$DATABASE_ALREADY_EXISTS" ]; then
    docker_verify_minimum_env

    # check dir permissions to reduce likelihood of half-initialized database
    ls /docker-entrypoint-initdb.d/ >/dev/null

    docker_init_database_dir
    mogdb_setup_hba_conf
    mogdb_setup_postgresql_conf
    mogdb_setup_mot_conf

    export PGPASSWORD="${PGPASSWORD:-$GS_PASSWORD}"
    docker_temp_server_start "$@"
    if [ -z "$SERVER_MODE" ] || [ "$SERVER_MODE" = "primary" ]; then
        docker_setup_db
        docker_setup_user
        docker_setup_rep_user
        docker_process_init_files /docker-entrypoint-initdb.d/*
    fi

    echo "Notify cluster other peers to add replconninfo configuration"
    notify_cluster_peers

    echo "Add cluster other peers replconninfo configuration to self"
    add_peers_to_self

    if [ -n "$SERVER_MODE" ] && [ "$SERVER_MODE" != "primary" ]; then
        docker_slave_full_backup
    fi
    docker_temp_server_stop
    unset PGPASSWORD

    echo
    echo 'mogdb  init process complete; ready for start up.'
    echo
else
    echo
    echo 'mogdb Database directory appears to contain a database; Skipping initialization'
    echo

    # recovering
    # ip changed ?

    # get ip from local
fi

exec $@