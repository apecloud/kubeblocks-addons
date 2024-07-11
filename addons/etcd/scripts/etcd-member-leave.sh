#!/bin/bash

set -exo pipefail

ENDPOINTS=$KB_LEAVE_MEMBER_POD_IP:2379
ETCDID=$(etcdctl --endpoints=$ENDPOINTS endpoint status | awk -F', ' '{print $2}')
etcdctl --endpoints=$ENDPOINTS member remove $ETCDID