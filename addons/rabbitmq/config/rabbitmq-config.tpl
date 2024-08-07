{{- $log_root := getVolumePathByName ( index $.podSpec.containers 0 ) "log" }}
{{- $rabbitmq_root := getVolumePathByName ( index $.podSpec.containers 0 ) "data" }}
{{- $rabbitmq_port_info := getPortByName ( index $.podSpec.containers 0 ) "amqp" }}
{{- $phy_memory := getContainerMemory ( index $.podSpec.containers 0 ) }}

# require port
{{- $rabbitmq_port := 5672 }}
{{- if $rabbitmq_port_info }}
{{- $rabbitmq_port = $rabbitmq_port_info.containerPort }}
{{- end }}

# rabbitmq.conf

## DEFAULT SETTINGS ARE NOT MEANT TO BE TAKEN STRAIGHT INTO PRODUCTION
## see https://www.rabbitmq.com/configure.html for further information
## on configuring RabbitMQ

## allow access to the guest user from anywhere on the network
## https://www.rabbitmq.com/access-control.html#loopback-users
## https://www.rabbitmq.com/production-checklist.html#users
loopback_users.guest = false

## Send all logs to stdout/TTY. Necessary to see logs when running via
## a container
log.console = true
log.console.level = info

queue_master_locator                       = min-masters
disk_free_limit.absolute                   = 2GB
cluster_partition_handling                 = pause_minority
cluster_formation.peer_discovery_backend   = rabbit_peer_discovery_k8s
cluster_formation.k8s.host                 = kubernetes.default
cluster_formation.k8s.address_type         = hostname
# cluster_formation.target_cluster_size_hint = 1
cluster_formation.k8s.service_name         = {{ .KB_CLUSTER_NAME }}-rabbitmq-headless
cluster_name                               = {{ .KB_CLUSTER_NAME }}

listeners.tcp.1 = :::{{ $rabbitmq_port }}
