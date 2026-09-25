#!/bin/bash
set -euo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/dolt}"

if [[ "$DATA_DIR" != /* || "$DATA_DIR" == "/" ]]; then
  echo "invalid DATA_DIR: ${DATA_DIR}" >&2
  exit 1
fi

echo "DoltDB logical restore is applied in the postReady stage after doltserver starts."
