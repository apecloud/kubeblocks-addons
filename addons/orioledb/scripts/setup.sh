#!/bin/bash
set -e

mkdir -p /postgresql/conf

cp /postgresql/mount_conf/postgresql.conf /postgresql/conf/
cp /postgresql/mount_conf/pg_hba.conf /postgresql/conf/

chown -R postgres:postgres /postgresql/conf
chmod 644 /postgresql/conf/*
chmod 755 /postgresql/conf

export PGCONF=/postgresql/conf

/tools/syncer --port '3601' -- docker-entrypoint.sh postgres --config-file=$PGCONF/postgresql.conf --hba-file=$PGCONF/pg_hba.conf

