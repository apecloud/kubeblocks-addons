#!/bin/bash
set -exo pipefail

# shellcheck disable=SC1091
. "/scripts/common.sh"



# Shellspec magic
setup_shellspec

# main
load_common_library
etcd_role=$(get_etcd_role)
echo -n "$etcd_role"