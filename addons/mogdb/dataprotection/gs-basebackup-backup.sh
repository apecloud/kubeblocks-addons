#set -e
#set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export PGPASSWORD=${DP_DB_PASSWORD}

trap handle_exit EXIT

START_TIME=`get_current_time`
BACKUP_TMPDIR="/tmp"

if [ ! -f /usr/bin/expect ]; then
  OLD_LD_LIBRARY_PATH="${LD_LIBRARY_PATH}"
  unset LD_LIBRARY_PATH

  apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y expect

  export LD_LIBRARY_PATH="${OLD_LD_LIBRARY_PATH}"
fi

/usr/bin/expect <<-EOF
set time 30
spawn gs_basebackup -Ft -Pv -c fast -Xf -D ${BACKUP_TMPDIR} -h ${DP_DB_HOST} -U ${DP_DB_USER} -z -W
expect "Password:"
send "${DP_DB_PASSWORD}\n"
send_user "\ngs_backup successful"

expect eof
EOF

BACKUP_TAR_FILE="${BACKUP_TMPDIR}/base.tar.gz"
if [ ! -f "${BACKUP_TAR_FILE}" ]; then
  echo "Backup tar file not exist"
  exit 1
fi

datasafed push "$BACKUP_TAR_FILE" "/${DP_BACKUP_NAME}.tar.gz"

# stat and save the backup information
stat_and_save_backup_info $START_TIME