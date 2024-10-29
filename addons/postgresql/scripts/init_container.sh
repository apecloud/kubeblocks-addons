#!/bin/bash
set -o errexit
set -e
mkdir -p /home/postgres/pgdata/conf
chmod +777 -R /home/postgres/pgdata/conf
cp /home/postgres/conf/postgresql.conf /home/postgres/pgdata/conf
chmod +777 /home/postgres/pgdata/conf/postgresql.conf

postgres_log_dir="/home/postgres/pgdata/logs/"
postgres_scripts_log_file="${postgres_log_dir}/scripts.log"
mkdir -p "$postgres_log_dir"
chmod -R +777 "$postgres_log_dir"
touch "$postgres_scripts_log_file"
chmod 666 "$postgres_scripts_log_file"
