#!/bin/bash
set -o errexit
set -e
mkdir -p /opt/bitnami/pgbouncer/conf/ /opt/bitnami/pgbouncer/logs/ /opt/bitnami/pgbouncer/tmp/
cp /home/pgbouncer/conf/pgbouncer.ini /opt/bitnami/pgbouncer/conf/
echo "\"$POSTGRESQL_USERNAME\" \"$POSTGRESQL_PASSWORD\"" > /opt/bitnami/pgbouncer/conf/userlist.txt
# shellcheck disable=SC2129
echo -e "\\n[databases]" >> /opt/bitnami/pgbouncer/conf/pgbouncer.ini
echo "postgres=host=$KB_POD_IP port=5432 dbname=postgres" >> /opt/bitnami/pgbouncer/conf/pgbouncer.ini
echo "*=host=$KB_POD_IP port=5432" >> /opt/bitnami/pgbouncer/conf/pgbouncer.ini
chmod +777 /opt/bitnami/pgbouncer/conf/pgbouncer.ini
chmod +777 /opt/bitnami/pgbouncer/conf/userlist.txt

# Try to add user
useradd pgbouncer 2>/dev/null || true

# NOTE:
# On Oracle Linux Server (especially in OKE environment), useradd command may fail with error:
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
    echo "Warning: pgbouncer user or group creation may have issues"
fi

chown -R pgbouncer:pgbouncer /opt/bitnami/pgbouncer/conf/ /opt/bitnami/pgbouncer/logs/ /opt/bitnami/pgbouncer/tmp/

su pgbouncer -c "/opt/bitnami/scripts/pgbouncer/run.sh"
