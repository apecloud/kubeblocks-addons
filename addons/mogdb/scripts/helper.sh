#!/bin/bash
#

set -ex
cat >>/home/omm/.profile <<-EOF
export PGHOST="/var/lib/mogdb/tmp"
EOF
source /home/omm/.profile
while true;do
  ncat -l 6543 >/tmp/remote.info
  read host_name remote_ip < /tmp/remote.info
  [[ "$host_name" =~ -([0-9]+)$ ]] || exit 1
  remote_ordinal=${BASH_REMATCH[1]}

  if [ -n "$PGPORT" ];then
    ha_port=$(expr $PGPORT + 1)
    ha_service_port=$(expr $PGPORT + 2)
  else
    ha_port=$(expr 5432 + 1)
    ha_service_port=$(expr 5432 + 2)
  fi

  repl_conn_info="replconninfo${remote_ordinal} = 'localhost=$PodIP localport=${ha_port} localservice=${ha_service_port} remotehost=$remote_ip remoteport=${ha_port} remoteservice=${ha_service_port}'"

  su - omm -c "gs_guc reload -D $PGDATA -c \"${repl_conn_info}\""
done