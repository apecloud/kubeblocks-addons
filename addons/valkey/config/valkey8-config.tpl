# Valkey 8.x default configuration template.
# This file is rendered as a Go template by KubeBlocks.
# Available variables correspond to the vars[] in ComponentDefinition.
# e.g. {{ $.PHY_MEMORY }} resolves to the container memory limit in bytes.
#
# The startup script (valkey-start.sh) appends runtime-dynamic settings
# (port, requirepass, replicaof, aclfile) to /etc/valkey/valkey.conf and
# includes this file via the "include" directive.

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

# Replication
replica-serve-stale-data yes
replica-read-only yes
repl-diskless-sync yes
repl-diskless-sync-delay 5
repl-diskless-load disabled
repl-disable-tcp-nodelay no
replica-priority 100

# AOF
appendonly yes
appendfilename "appendonly.aof"
appenddirname "appendonlydir"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
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

# IO threads — scale with available CPU, capped at 8.
# Setting 1 disables multi-threading (same as not setting it).
# Valkey docs recommend 2-4 for servers with 4+ CPUs.
{{- $cpu := default 0 $.PHY_CPU | int }}
{{- if gt $cpu 0 }}
io-threads {{ min (max $cpu 1) 8 }}
{{- else }}
io-threads 2
{{- end }}
io-threads-do-reads yes

# Memory policy
maxmemory-policy volatile-lru
{{- $mem := default 0 $.PHY_MEMORY | int }}
{{- if gt $mem 0 }}
maxmemory {{ mulf $mem 0.8 | int }}
{{- end }}

# TLS (enabled via runtime var)
{{- if eq (index $ "TLS_ENABLED") "true" }}
tls-cert-file {{ $.TLS_MOUNT_PATH }}/tls.crt
tls-key-file  {{ $.TLS_MOUNT_PATH }}/tls.key
tls-ca-cert-file {{ $.TLS_MOUNT_PATH }}/ca.crt
tls-auth-clients no
tls-replication yes
port 0
{{- end }}
