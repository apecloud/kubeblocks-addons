#!/bin/bash

readarray -t topics < <(datasafed pull topics.txt -)
for topic in "${topics[@]}"; do
  kafkactl create topic "$topic"
  datasafed pull "data/${topic}.json" - | kafkactl produce "$topic" --input-format=json
done
