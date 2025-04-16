# mongod.conf
# for documentation of all options, see:
#   http://docs.mongodb.org/manual/reference/configuration-options/

# TODO: .Values.dataMountPath
{{- $mongodb_root := "/data/mongodb" }}
{{- $mongodb_port := $.KB_SERVICE_PORT }}

# where and how to store data.
storage:
  dbPath: {{ $mongodb_root }}/db
  directoryPerDB: true

# where to write logging data.
{{ block "logsBlock" . }}
systemLog:
  destination: file
  quiet: false
  logAppend: false
  logRotate: rename
  path: /data/mongodb/logs/mongodb.log
  verbosity: 0
{{ end }}

# network interfaces
net:
  port: {{ $mongodb_port }}
  unixDomainSocket:
    enabled: false
    pathPrefix: {{ $mongodb_root }}/tmp
  ipv6: false
  bindIpAll: true
  #bindIp:

# replica set options
replication:
  replSetName: replicaset
  enableMajorityReadConcern: true

# sharding options
#sharding:
  #clusterRole:

# process management options
processManagement:
   fork: false
   pidFilePath: {{ $mongodb_root }}/tmp/mongodb.pid

# set parameter options
setParameter:
   enableLocalhostAuthBypass: true

# security options
security:
  authorization: enabled
  keyFile: /etc/mongodb/keyfile
