#!/bin/bash

# topics.txt format is like:
# (topic name)             (partitions)   (replication factor)
# topic1                   1              1
# topic2                   1              1
#
# We also ignores the __consumer_offsets topic as offsets won't be backuped up.
echo "getting topics..."
kafkactl get topics | tail -n +2 | grep -v __consumer_offsets | datasafed push - topics.txt
readarray -t topics < <(kafkactl get topics -o compact | grep -v  __consumer_offsets)

for topic in "${topics[@]}"; do
  echo "backing up ${topic}..."
  kafkactl consume "${topic}" --from-beginning --print-keys --print-timestamps --exit --print-headers -o json-raw | datasafed push - "data/${topic}.json"
done

# use datasafed to get backup size
# if we do not write into $DP_BACKUP_INFO_FILE, the backup job will stuck
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
DP_save_backup_status_info "$TOTAL_SIZE"
