#!/bin/bash
set -o errexit
set -e
mkdir -p /home/postgres/pgdata/conf
chmod +777 -R /home/postgres/pgdata/conf
cp /home/postgres/conf/postgresql.conf /home/postgres/pgdata/conf
chmod +777 /home/postgres/pgdata/conf/postgresql.conf

postgres_walg_dir="/home/postgres/pgdata/wal-g"
mkdir -p "$postgres_walg_dir"
cp /spilo-init/bin/wal-g ${postgres_walg_dir}/wal-g