#!/bin/bash

set -eo pipefail

cat json-raw.json  | kafkactl produce new2 --input-format=json
