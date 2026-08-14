#!/bin/bash
set -euo pipefail

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

DB_USER="${MYSQL_ADMIN_USER:-${DP_DB_USER}}"
DB_PASSWORD="${MYSQL_ADMIN_PASSWORD:-${DP_DB_PASSWORD}}"
export MYSQL_PWD="$DB_PASSWORD"

deadline=$(($(date +%s) + 180))
until mariadb --skip-ssl -u "$DB_USER" -h "$DP_DB_HOST" -P "$DP_DB_PORT" -e "SELECT 1" >/dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "timed out waiting for MariaDB before PITR replay" >&2
    exit 1
  fi
  sleep 2
done

rm -rf "$PITR_DIR"
mkdir -p "$PITR_DIR"
restore_datetime=$(date -u -d "$DP_RESTORE_TIME" '+%Y-%m-%d %H:%M:%S')

anchor_info="$VOLUME_DATA_DIR/.kb-pitr-binlog-info"
if [ ! -s "$anchor_info" ]; then
  echo "base backup binlog coordinates are missing: $anchor_info" >&2
  exit 1
fi
anchor_file=$(awk 'NR == 1 {print $1}' "$anchor_info")
anchor_position=$(awk 'NR == 1 {print $2}' "$anchor_info")
anchor_gtid=$(awk 'NR == 1 {print $3}' "$anchor_info")
if [ -z "$anchor_file" ] || [ -z "$anchor_position" ]; then
  echo "invalid base backup binlog coordinates in $anchor_info" >&2
  exit 1
fi

datasafed list -f --recursive /binlog | sort > "$PITR_DIR/archive.list"
declare -a replay_files=()
while IFS= read -r object; do
  [ -n "$object" ] || continue
  local_file="$PITR_DIR/$(basename "$object")"
  datasafed pull -d zstd-fastest "$object" "$local_file"
  replay_files+=("$local_file")
done < "$PITR_DIR/archive.list"

if [ "${#replay_files[@]}" -eq 0 ]; then
  echo "no archived MariaDB binlogs are available" >&2
  exit 1
fi

# mariadb-backup is non-blocking: prepared data pages can contain transactions
# newer than the coordinate recorded in mariadb_backup_binlog_info. In
# addition, the freshly restored server emits its own bootstrap GTIDs before
# postReady runs. Replaying mariadb-binlog's gtid_seq_no directives verbatim
# can therefore request an older sequence in the same domain and fail under
# gtid_strict_mode. Keep the transaction payload and boundaries, but let the
# restored primary allocate fresh, monotonic GTIDs; those transactions are
# then replicated normally to its new secondaries.
strip_source_gtid_sequence() {
  sed '/SET @@session\.gtid_seq_no=/d'
}

if [ -n "$anchor_gtid" ]; then
  mariadb-binlog --skip-gtid-strict-mode --start-position="$anchor_gtid" \
    --stop-datetime="$restore_datetime" "${replay_files[@]}" \
    | strip_source_gtid_sequence \
    | mariadb --skip-ssl -u "$DB_USER" -h "$DP_DB_HOST" -P "$DP_DB_PORT"
else
  declare -a position_files=()
  anchor_found=false
  for file in "${replay_files[@]}"; do
    if [[ "$(basename "$file")" == *-"$anchor_file" ]]; then
      anchor_found=true
    fi
    if [ "$anchor_found" = true ]; then
      position_files+=("$file")
    fi
  done
  if [ "${#position_files[@]}" -eq 0 ]; then
    echo "archive does not contain base binlog $anchor_file" >&2
    exit 1
  fi
  mariadb-binlog --skip-gtid-strict-mode --start-position="$anchor_position" \
    --stop-datetime="$restore_datetime" "${position_files[@]}" \
    | strip_source_gtid_sequence \
    | mariadb --skip-ssl -u "$DB_USER" -h "$DP_DB_HOST" -P "$DP_DB_PORT"
fi

rm -f "${replay_files[@]}"

echo "MariaDB binlog replay completed through ${DP_RESTORE_TIME}"
