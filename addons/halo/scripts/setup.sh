#!/bin/bash
set -o errexit
set -o nounset

. /halo-scripts/libpostgresql.sh

export POSTGRESQL_INIT_MAX_TIMEOUT="${POSTGRESQL_INIT_MAX_TIMEOUT:-15}"
export POSTGRESQL_BIN_DIR="/u01/app/halo/product/dbms/14/bin"
export POSTGRESQL_CONF_DIR="/kubeblocks"
export POSTGRESQL_CONF_FILE="$POSTGRESQL_CONF_DIR/postgresql.conf"
export POSTGRESQL_MASTER_HOST=$KB_0_HOSTNAME
KB_0_POD_NAME_PREFIX="${KB_0_HOSTNAME%%\.*}"

if [ ! -d "$POSTGRESQL_CONF_DIR" ];then
  cp -r /var/lib/halo/conf kubeblocks/
fi


# default standby when pgdata is not empty
if [ "$(ls -A ${PGDATA})" ]; then
  # touch "$PGDATA"/standby.signal
  echo "postgresql has been initialized"
else
  if [ "$KB_0_POD_NAME_PREFIX" != "$KB_POD_NAME" ]; then
    # Ensure 'daemon' user exists when running as 'root'
    am_i_root && ensure_user_exists "$HALO_USER"
    postgresql_slave_init_db
    primary_conninfo="host=$KB_0_HOSTNAME port=$HALOPORT user=$HALO_USER password=$HALO_PASSWORD application_name=$KB_POD_NAME"
    postgresql_set_property "primary_conninfo" "$primary_conninfo" "$POSTGRESQL_CONF_FILE"
    touch "$PGDATA"/standby.signal
  fi
 
fi

echo "start setup"

docker-entrypoint.sh --config-file="$POSTGRESQL_CONF_FILE" --hba_file="$POSTGRESQL_CONF_DIR/pg_hba.conf"