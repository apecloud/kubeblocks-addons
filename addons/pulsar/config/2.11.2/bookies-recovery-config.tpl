httpServerEnabled=true
httpServerPort=8000
prometheusStatsHttpPort=8000
useHostNameAsBookieID=true
# how long to wait, in seconds, before starting autorecovery of a lost bookie.
# TODO: set to 0 after opsRequest for rollingUpdate supports hooks
lostBookieRecoveryDelay=300

zkServers={{ .ZOOKEEPER_SERVERS }}