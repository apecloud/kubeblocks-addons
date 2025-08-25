#!/bin/bash

pgbouncer_template_conf_file="/home/pgbouncer/conf/pgbouncer.ini"
pgbouncer_conf_dir="/opt/bitnami/pgbouncer/conf/"
pgbouncer_log_dir="/opt/bitnami/pgbouncer/logs/"
pgbouncer_tmp_dir="/opt/bitnami/pgbouncer/tmp/"
pgbouncer_conf_file="/opt/bitnami/pgbouncer/conf/pgbouncer.ini"
pgbouncer_user_list_file="/opt/bitnami/pgbouncer/conf/userlist.txt"

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/kb-scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

build_pgbouncer_conf() {
  if is_empty "$POSTGRESQL_USERNAME" || is_empty "$POSTGRESQL_PASSWORD" || is_empty "$CURRENT_POD_IP"; then
    echo "POSTGRESQL_USERNAME, POSTGRESQL_PASSWORD or CURRENT_POD_IP is not set. Exiting..."
    exit 1
  fi

  mkdir -p $pgbouncer_conf_dir $pgbouncer_log_dir $pgbouncer_tmp_dir
  cp $pgbouncer_template_conf_file $pgbouncer_conf_dir
  echo "\"$POSTGRESQL_USERNAME\" \"$POSTGRESQL_PASSWORD\"" > $pgbouncer_user_list_file
  # shellcheck disable=SC2129
  echo -e "\\n[databases]" >> $pgbouncer_conf_file
  echo "postgres=host=$CURRENT_POD_IP port=5432 dbname=postgres" >> $pgbouncer_conf_file
  echo "*=host=$CURRENT_POD_IP port=5432" >> $pgbouncer_conf_file
  chmod 777 $pgbouncer_conf_file
  chmod 777 $pgbouncer_user_list_file

  # Try to add user
  useradd pgbouncer 2>/dev/null || true

  # NOTE:
  # On Oracle Linux Server (especially in OKE environment) or OpenShift, useradd command may fail with error:
  # "useradd: failure while writing changes to /etc/group"
  # In this case, the user might be created but the group is not properly added to /etc/group file.
  # This causes subsequent chown operations to fail. We need to handle this by:
  # 1. Checking if user exists after useradd attempt
  # 2. Separately checking if group exists (even if user was created)
  # 3. Manually adding missing entries to /etc/passwd and /etc/group files when needed

  # Check if user exists
  if ! id "pgbouncer" >/dev/null 2>&1; then
      echo "useradd failed, attempting manual user creation..."

      # Get next available UID/GID
      next_uid=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $3}' /etc/passwd | sort -n | tail -1)
      next_uid=$((next_uid + 1))

      # Add user to /etc/passwd
      echo "pgbouncer:x:$next_uid:$next_uid:pgbouncer user:/nonexistent:/bin/false" >> /etc/passwd
      echo "Added pgbouncer user to /etc/passwd"
  fi

  # Check if group exists (even if user was created by useradd)
  if ! getent group pgbouncer >/dev/null 2>&1; then
      echo "pgbouncer group not found, creating manually..."

      # Get the user's GID if user exists
      if id "pgbouncer" >/dev/null 2>&1; then
          user_gid=$(id -g pgbouncer)
          echo "pgbouncer:x:$user_gid:" >> /etc/group
          echo "Added pgbouncer group with GID $user_gid to /etc/group"
      else
          # Fallback: use next available GID
          next_gid=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $3}' /etc/group | sort -n | tail -1)
          next_gid=$((next_gid + 1))
          echo "pgbouncer:x:$next_gid:" >> /etc/group
          echo "Added pgbouncer group with GID $next_gid to /etc/group"
      fi
  fi

  # Verify both user and group exist
  if id "pgbouncer" >/dev/null 2>&1 && getent group pgbouncer >/dev/null 2>&1; then
      echo "pgbouncer user and group are ready"
  else
      echo "Failed to create pgbouncer user or group. Exiting..."
      exit 1
  fi

  chown -R pgbouncer:pgbouncer $pgbouncer_conf_dir $pgbouncer_log_dir $pgbouncer_tmp_dir
}

start_pgbouncer() {
  # https://github.com/bitnami/containers/blob/main/bitnami/pgbouncer/1/debian-12/rootfs/opt/bitnami/scripts/pgbouncer/run.sh
  su pgbouncer -c "/opt/bitnami/scripts/pgbouncer/run.sh"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
build_pgbouncer_conf
start_pgbouncer
