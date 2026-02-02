#!/bin/bash
set -o errexit
set -e

postgres_template_conf_file="/home/postgres/conf/postgresql.conf"
postgres_conf_dir="/home/postgres/pgdata/conf/"
postgres_conf_file="/home/postgres/pgdata/conf/postgresql.conf"
postgres_walg_dir="/home/postgres/pgdata/wal-g"

# Create config directory
mkdir -p "$postgres_conf_dir"

# Copy the template config file
cp "$postgres_template_conf_file" "$postgres_conf_dir"

# Set permissions
# Note: We rely on Kubernetes fsGroup (103) to set the correct group ownership
# The fsGroup mechanism automatically sets the group of files in mounted volumes to 103 (postgres group)
# With 664 permission, the postgres user (which is in group 103) can read and write the file
chmod 755 "$postgres_conf_dir"
chmod 664 "$postgres_conf_file"

# Copy wal-g binary
mkdir -p "$postgres_walg_dir"
cp /spilo-init/bin/wal-g ${postgres_walg_dir}/wal-g
