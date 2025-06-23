#!/bin/sh
sql="DROP HOSTS \"$POD_FQDN\":9779"
# TODO: use space and SUBMIT JOB BALANCE DATA REMOVE <ip:port> first, then remove host.
# 目前社区版balance data不稳定，会有问题，所以先不支持这个功能。 如果进行缩replicas, 下面命名会一直报错。
/usr/local/nebula/console/nebula-console --addr $GRAPHD_SVC_NAME --port $GRAPHD_SVC_PORT --user root --password nebula -e "${sql}"