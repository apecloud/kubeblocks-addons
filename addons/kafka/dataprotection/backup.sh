#!/bin/bash

# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists
function handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit $exit_code
  fi
}

trap handle_exit EXIT

# topics.txt format is like:
# (topic name)             (partitions)   (replication factor)
# topic1                   1              1
# topic2                   1              1
#
# We also ignores the __consumer_offsets topic as offsets won't be backuped up.
echo "getting topics..."
topic_table="/tmp/kafka-topics.txt"
topic_stderr="/tmp/kafkactl-get-topics.stderr"
topic_retries="${KAFKA_BACKUP_TOPIC_DISCOVERY_RETRIES:-12}"
topic_attempt=1
while true; do
  if kafkactl get topics > "${topic_table}" 2> "${topic_stderr}"; then
    break
  fi
  rc=$?
  echo "kafkactl get topics failed attempt=${topic_attempt}/${topic_retries} rc=${rc}"
  cat "${topic_stderr}" || true
  if [[ "${topic_attempt}" -ge "${topic_retries}" ]]; then
    exit "${rc}"
  fi
  topic_attempt=$((topic_attempt + 1))
  sleep 5
done

topic_list=$(awk 'NR > 1 && $1 != "__consumer_offsets" {print $1, $2, $3}' "${topic_table}")
if [[ -z $topic_list ]]; then
  echo "nothing to backup"
  DP_save_backup_status_info 0
  exit 0
fi
printf '%s\n' "${topic_list}" | datasafed push - topics.txt
readarray -t topics < <(awk 'NR > 1 && $1 != "__consumer_offsets" {print $1}' "${topic_table}")

for topic in "${topics[@]}"; do
  echo "backing up ${topic}..."
  kafkactl consume "${topic}" --from-beginning --print-keys --print-timestamps --exit --print-headers -o json-raw | datasafed push - "data/${topic}.json"
done

# use datasafed to get backup size
# if we do not write into $DP_BACKUP_INFO_FILE, the backup job will stuck
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
DP_save_backup_status_info "$TOTAL_SIZE"
