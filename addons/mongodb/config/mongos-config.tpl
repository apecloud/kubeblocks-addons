# mongod.conf
# for documentation of all options, see:
#   http://docs.mongodb.org/manual/reference/configuration-options/

{{- $mongodb_root := getVolumePathByName ( index $.podSpec.containers 0 ) "data" }}
{{- $mongodb_port_info := getPortByName ( index $.podSpec.containers 0 ) "mongodb" }}

# require port
{{- $mongodb_port := 27017 }}
{{- if $mongodb_port_info }}
{{- $mongodb_port = $mongodb_port_info.containerPort }}
{{- end }}

# network interfaces
net:
  port: {{ $mongodb_port }}
  unixDomainSocket:
    enabled: false
    pathPrefix: {{ $mongodb_root }}/tmp
  ipv6: false
  bindIpAll: true
  #bindIp:

# sharding:

# security options
security:
  keyFile: /etc/mongodb/keyfile
