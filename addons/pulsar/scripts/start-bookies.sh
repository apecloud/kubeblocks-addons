#!/bin/bash
set -x

python3 /kb-scripts/merge_pulsar_config.py conf/bookkeeper.conf /opt/pulsar/conf/bookkeeper.conf;
bin/apply-config-from-env.py conf/bookkeeper.conf;

journalDirectories=$(grep 'journalDirectories' /pulsar/conf/bookkeeper.conf | grep -v '#' | cut -d '=' -f 2)
ledgerDirectories=$(grep 'ledgerDirectories' /pulsar/conf/bookkeeper.conf | grep -v '#' | cut -d '=' -f 2)
mkdir -p ${journalDirectories}/current && mkdir -p ${ledgerDirectories}/current
journalRes=`ls -A ${journalDirectories}/current`
ledgerRes=`ls -A ${ledgerDirectories}/current`

if [[ -z $journalRes && -z $ledgerRes ]]; then
   echo "journalRes and ledgerRes directory is empty, check whether the remote cookies is empty either"
   host_ip_port="${KB_POD_FQDN}${cluster_domain}:3181"
   zkLedgersRootPath=$(grep 'zkLedgersRootPath' /pulsar/conf/bookkeeper.conf | grep -v '#' | cut -d '=' -f 2)
   zNode="${zkLedgersRootPath}/cookies/${host_ip_port}"

   # if current dir are empty but bookieId exists in zookeeper, delete it
   if zkURL=${zkServers} python3 /kb-scripts/zookeeper.py get ${zNode}; then
     echo "Warning: exist redundant bookieID ${zNode}"
     zkURL=${zkServers} python3 /kb-scripts/zookeeper.py delete ${zNode};
   fi
fi

OPTS="${OPTS} -Dlog4j2.formatMsgNoLookups=true" exec bin/pulsar bookie;