#!/bin/bash

readarray -t topics < <(kafkactl get topics -o compact)
printf "%s\n" "${topics[@]}" | datasafed push - topics.txt
for topic in "${topics[@]}"; do
  kafkactl consume "${topic}" --from-beginning --print-keys --print-timestamps --exit --print-headers -o json-raw | datasafed push - "data/${topic}.json"
done

# use datasafed to get backup size
# if we do not write into $DP_BACKUP_INFO_FILE, the backup job will stuck
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
DP_save_backup_status_info "$TOTAL_SIZE"
