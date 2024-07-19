#!/bin/bash

set -exo pipefail

ENDPOINTS=$KB_LEAVE_MEMBER_POD_IP:2379
ETCDID=$(execEtcdctl $ENDPOINTS endpoint status | awk -F', ' '{print $2}')

execEtcdctl $ENDPOINTS member remove $ETCDID