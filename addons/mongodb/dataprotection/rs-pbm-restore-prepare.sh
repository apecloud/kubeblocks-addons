#!/bin/bash
set -e
set -o pipefail

mkdir -p ${MOUNT_DIR}/tmp

cd ${MOUNT_DIR}/tmp && touch mongodb_pbm.backup