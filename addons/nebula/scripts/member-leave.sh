#!/bin/sh
sql="DROP HOSTS \"$POD_FQDN\":9779"
/usr/local/nebula/console/nebula-console --addr $GRAPHD_SVC_NAME --port $GRAPHD_SVC_PORT --user root --password nebula -e "${sql}"