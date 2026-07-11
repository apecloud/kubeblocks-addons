# Valkey Cluster (sharding) configuration template.
# This file is rendered as a Go template by KubeBlocks.
# Available variables correspond to the vars[] in ComponentDefinition.
#
# The startup script (valkey-cluster-server-start.sh) appends runtime-dynamic
# settings (port, cluster bus port, announce addresses, requirepass, aclfile)
# and includes this file via the "include" directive. Replication inside a
# shard is managed by the cluster itself (CLUSTER commands), never by
# REPLICAOF, so this template must not carry replicaof directives.

bind * -::*
tcp-backlog 511
timeout 0
tcp-keepalive 300
daemonize no
pidfile /var/run/valkey_6379.pid

loglevel notice
logfile "/data/running.log"

databases 16
always-show-logo no
set-proc-title yes

# Persistence
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
rdb-del-sync-files no
dir /data

# Replication (intra-shard primary->replica)
replica-serve-stale-data yes
replica-read-only yes
repl-diskless-sync yes
repl-diskless-sync-delay 5
repl-diskless-load disabled
repl-disable-tcp-nodelay no

# Cluster (Valkey Cluster / sharding mode)
# cluster-config-file MUST live on the data volume: nodes.conf carries this
# node's cluster identity (CLUSTER MYID) and must survive pod restarts.
cluster-enabled yes
cluster-config-file /data/nodes.conf
cluster-node-timeout 5000
# A replica whose data is too stale never wins election; 0 disables the
# validity factor so any connected replica may fail over (engine default
# is 10; 0 matches the HA-first posture for in-cluster deployments).
cluster-replica-validity-factor 0
# Require full slot coverage before serving: fail loudly on missing slots
# instead of silently serving a partial keyspace.
cluster-require-full-coverage yes

# AOF
appendonly yes
appendfilename "appendonly.aof"
appenddirname "appendonlydir"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 67108864
aof-use-rdb-preamble yes

# Slow log
slowlog-log-slower-than 10000
slowlog-max-len 128

# Data structures
hash-max-listpack-entries 128
hash-max-listpack-value 64
list-max-listpack-size -2
set-max-intset-entries 512
zset-max-listpack-entries 128
zset-max-listpack-value 64

# IO threads -- use roughly half of available CPUs, capped at 8.
# Setting 1 disables multi-threading (same as not setting it).
{{- $cpu := index . "PHY_CPU" | default 0 | int }}
{{- if gt $cpu 1 }}
io-threads {{ min (max (div $cpu 2) 1) 8 }}
{{- else }}
io-threads 1
{{- end }}
io-threads-do-reads yes

# Memory policy
# noeviction is the Valkey upstream default: when maxmemory is reached,
# writes fail loudly instead of silently evicting data. For a database
# service that is the safe default; cache deployments that prefer
# eviction can set maxmemory-policy (dynamic parameter) per cluster.
maxmemory-policy noeviction
{{- $mem := index . "PHY_MEMORY" | default 0 | int }}
{{- if gt $mem 0 }}
maxmemory {{ mulf $mem 0.8 | int }}
{{- end }}

# TLS: unsupported on the cluster topology in v1. The previous gated block
# here could never activate (no TLS_ENABLED var was supplied) and partial
# re-wiring risks a silent-plaintext or split-brain config; cluster TLS
# support must land as one complete change (cmpd tls decl + vars +
# tls-port/port swap + tls-cluster bus + client flags) with live TLS
# acceptance. See cluster-tls-boundary contract spec.
