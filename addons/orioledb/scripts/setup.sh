#!/bin/bash
set -e

mkdir -p /postgresql/conf
# copy the postgresql.conf and pg_hba.conf to the conf directory
cp /postgresql/mount_conf/postgresql.conf /postgresql/conf/
cp /postgresql/mount_conf/pg_hba.conf /postgresql/conf/

chown -R postgres:postgres /postgresql/conf
chmod 644 /postgresql/conf/*
chmod 755 /postgresql/conf

# create the data directory
mkdir -p /postgresql/mount_volume/pgdata
chown -R postgres:postgres /postgresql/mount_volume/pgdata
chmod 700 /postgresql/mount_volume/pgdata

export PGCONF=/postgresql/conf
export PGDATA=/postgresql/mount_volume/pgdata

/tools/syncer --port '3601' -- docker-entrypoint.sh postgres --config-file=$PGCONF/postgresql.conf --hba-file=$PGCONF/pg_hba.conf

