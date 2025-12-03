#!/bin/bash

echo "getting topics..."
if [[ -z $(datasafed list topics.txt) ]]; then
  echo "restore from an empty backup! doing nothing..."
  exit 0
fi
readarray -t lines < <(datasafed pull topics.txt -)
for line in "${lines[@]}"; do
  read -r topic partitions replication <<< "$line"
  echo "restoring ${topic}..."
  kafkactl create topic "$topic" --partitions "$partitions" --replication-factor "$replication"
  datasafed pull "data/${topic}.json" - | kafkactl produce "$topic" --input-format=json
done
