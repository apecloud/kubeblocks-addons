//Valkey parameter constraints, generated from the upstream release lines
//8.0 and 8.1 (src/config.c) of https://github.com/valkey-io/valkey.
//
//This file is part of KubeBlocks project
//
//This program is free software: you can redistribute it and/or modify
//it under the terms of the GNU Affero General Public License as published by
//the Free Software Foundation, either version 3 of the License, or
//(at your option) any later version.
//
//This program is distributed in the hope that it will be useful
//but WITHOUT ANY WARRANTY; without even the implied warranty of
//MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//GNU Affero General Public License for more details.
//
//You should have received a copy of the GNU Affero General Public License
//along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
//One ComponentDefinition (valkey-8) serves both release lines, so this
//schema is the UNION of 8.0 and 8.1: a parameter that only exists in one of
//them carries an inline marker.  Parameters the addon owns are deliberately
//absent — TLS (written by scripts/valkey-start.sh from TLS_ENABLED), the data
//directory layout (PD immutableParameters), credentials / ACL storage,
//replication topology and announce addresses, container logging plumbing,
//module loading and Sentinel mode.

#ValkeyParameter: {

    "acl-pubsub-default"?: string & "resetchannels" | "allchannels"

    "acllog-max-len"?: int & >=1 & <=10000 | *128

    "active-defrag-cycle-max"?: int & >=1 & <=75 | *25

    "active-defrag-cycle-min"?: int & >=1 & <=75 | *1

    // only in 8.1
    "active-defrag-cycle-us"?: int | *500

    "active-defrag-ignore-bytes"?: int | *104857600

    "active-defrag-max-scan-fields"?: int & >=1 & <=1000000 | *1000

    "active-defrag-threshold-lower"?: int & >=1 & <=100 | *10

    "active-defrag-threshold-upper"?: int & >=1 & <=100 | *100

    "active-expire-effort"?: int & >=1 & <=10 | *1

    "activedefrag"?: string & "yes" | "no" | *"no"

    "activerehashing"?: string & "yes" | "no" | *"yes"

    "always-show-logo"?: string & "yes" | "no" | *"yes"

    "aof-disable-auto-gc"?: string & "yes" | "no"

    "aof-load-truncated"?: string & "yes" | "no" | *"yes"

    // legacy alias: aof_rewrite_cpulist
    "aof-rewrite-cpulist"?: string

    "aof-rewrite-incremental-fsync"?: string & "yes" | "no" | *"yes"

    "aof-timestamp-enabled"?: string & "yes" | "no"

    "aof-use-rdb-preamble"?: string & "yes" | "no" | *"yes"

    "appendfsync"?: string

    "appendonly"?: string & "yes" | "no" | *"no"

    "auto-aof-rewrite-min-size"?: string | *"64mb"

    "auto-aof-rewrite-percentage"?: int | *100

    "availability-zone"?: string

    // legacy alias: bgsave_cpulist
    "bgsave-cpulist"?: string

    "bind"?: string

    "bind-source-addr"?: string

    // legacy alias: bio_cpulist
    "bio-cpulist"?: string

    // legacy alias: lua-time-limit
    "busy-reply-threshold"?: int | *5000

    "client-default-resp"?: int | *2

    "client-output-buffer-limit"?: string

    "client-query-buffer-limit"?: int & >=1048576 & <=1073741824 | *1073741824

    "cluster-allow-pubsubshard-when-down"?: string & "yes" | "no"

    "cluster-allow-reads-when-down"?: string & "yes" | "no"

    "cluster-allow-replica-migration"?: string & "yes" | "no" | *"yes"

    "cluster-announce-bus-port"?: int | *0

    "cluster-announce-client-ipv4"?: string

    "cluster-announce-client-ipv6"?: string

    "cluster-announce-hostname"?: string

    "cluster-announce-human-nodename"?: string

    "cluster-announce-ip"?: string

    "cluster-announce-port"?: int | *0

    "cluster-announce-tls-port"?: int | *0

    "cluster-blacklist-ttl"?: int | *60

    "cluster-config-file"?: string

    "cluster-enabled"?: string & "yes" | "no"

    "cluster-link-sendbuf-limit"?: int | string | *0

    // only in 8.1
    "cluster-manual-failover-timeout"?: int | *5000

    "cluster-migration-barrier"?: int | *1

    "cluster-node-timeout"?: int | *15000

    "cluster-ping-interval"?: int | *0

    "cluster-port"?: int | *0

    "cluster-preferred-endpoint-type"?: string & "tls-dynamic" | "ip"

    // legacy alias: cluster-slave-no-failover
    "cluster-replica-no-failover"?: string & "yes" | "no" | *"no"

    // legacy alias: cluster-slave-validity-factor
    "cluster-replica-validity-factor"?: int | *10

    "cluster-require-full-coverage"?: string & "yes" | "no"

    "cluster-slot-stats-enabled"?: string & "yes" | "no" | *"no"

    // only in 8.1; legacy alias: slowlog-log-slower-than
    "commandlog-execution-slower-than"?: int | *10000

    // only in 8.1
    "commandlog-large-reply-max-len"?: int | *128

    // only in 8.1
    "commandlog-large-request-max-len"?: int | *128

    // only in 8.1
    "commandlog-reply-larger-than"?: int

    // only in 8.1
    "commandlog-request-larger-than"?: int

    // only in 8.1; legacy alias: slowlog-max-len
    "commandlog-slow-execution-max-len"?: int | *128

    "crash-log-enabled"?: string & "no" | "yes" | *"yes"

    "crash-memcheck-enabled"?: string & "no" | "yes" | *"yes"

    "databases"?: int | *16

    "debug-context"?: string

    "disable-thp"?: string & "yes" | "no" | *"yes"

    "dual-channel-replication-enabled"?: string & "yes" | "no" | *"no"

    // only in 8.0
    "dynamic-hz"?: string & "yes" | "no" | *"yes"

    "enable-debug-assert"?: string & "yes" | "no" | *"no"

    "enable-debug-command"?: string & "yes" | "no" | "local"

    "enable-module-command"?: string & "yes" | "no" | "local" | *"no"

    "enable-protected-configs"?: string & "yes" | "no" | "local" | *"no"

    "events-per-io-thread"?: int | *2

    "extended-redis-compatibility"?: string & "yes" | "no" | *"no"

    // legacy alias: hash-max-ziplist-entries
    "hash-max-listpack-entries"?: int | *512

    // legacy alias: hash-max-ziplist-value
    "hash-max-listpack-value"?: int | *64

    "hide-user-data-from-log"?: string & "yes" | "no" | *"yes"

    "hll-sparse-max-bytes"?: int & >=1 & <=16000 | *3000

    "hz"?: int

    "ignore-warnings"?: string & "ARM64-COW-BUG"

    // only in 8.1
    "import-mode"?: string & "yes" | "no" | *"no"

    "io-threads"?: int & >=2 & <=8 | *4

    // only in 8.0
    "io-threads-do-reads"?: string & "yes" | "no"

    "jemalloc-bg-thread"?: string & "yes" | "no" | *"yes"

    "key-load-delay"?: int | *0

    "latency-monitor-threshold"?: int | *0

    "latency-tracking"?: string & "yes" | "no"

    "latency-tracking-info-percentiles"?: string | *"50 99 999"

    "lazyfree-lazy-eviction"?: string & "yes" | "no" | *"no"

    "lazyfree-lazy-expire"?: string & "yes" | "no" | *"no"

    "lazyfree-lazy-server-del"?: string & "yes" | "no" | *"no"

    "lazyfree-lazy-user-del"?: string & "yes" | "no" | *"no"

    "lazyfree-lazy-user-flush"?: string & "yes" | "no" | *"no"

    "lfu-decay-time"?: int | *1

    "lfu-log-factor"?: int | *10

    "list-compress-depth"?: int | *0

    // legacy alias: list-max-ziplist-size
    "list-max-listpack-size"?: int | *-2

    "loading-process-events-interval-bytes"?: int

    "locale-collate"?: string | *""

    // only in 8.1
    "log-format"?: string

    // only in 8.1
    "log-timestamp-format"?: string

    "loglevel"?: string

    // legacy alias: lua-enable-deprecated-api
    "lua-enable-insecure-api"?: string & "yes" | "no" | *"no"

    "max-new-connections-per-cycle"?: int | *10

    "max-new-tls-connections-per-cycle"?: int | *1

    "maxclients"?: int | *10000

    "maxmemory"?: int | string | *0

    "maxmemory-clients"?: string | *"0"

    "maxmemory-eviction-tenacity"?: int & >=0 & <=100 | *10

    "maxmemory-policy"?: string & "volatile-lru" | "allkeys-lru" | "volatile-lfu" | "allkeys-lfu" | "volatile-random" | "allkeys-random" | "volatile-ttl" | "noeviction"

    "maxmemory-samples"?: int | *5

    // legacy alias: min-slaves-max-lag
    "min-replicas-max-lag"?: int | *10

    // legacy alias: min-slaves-to-write
    "min-replicas-to-write"?: int | *0

    "no-appendfsync-on-rewrite"?: string & "yes" | "no" | *"no"

    "notify-keyspace-events"?: string

    "oom-score-adj"?: string & "yes" | "no" | "absolute" | "relative" | *"no"

    "oom-score-adj-values"?: string | *"0 200 800"

    "port"?: int | *6379

    "prefetch-batch-max-size"?: int | *16

    "proc-title-template"?: string | *"{title} {listen-addr} {server-mode}"

    "propagation-error-behavior"?: string | *"ignore"

    "protected-mode"?: string & "yes" | "no" | *"yes"

    "proto-max-bulk-len"?: int & >=1048576 & <=536870912 | *536870912

    "rdb-del-sync-files"?: string & "yes" | "no" | *"no"

    "rdb-key-save-delay"?: int | *0

    "rdb-save-incremental-fsync"?: string & "yes" | "no" | *"yes"

    // only in 8.1
    "rdb-version-check"?: string

    "rdbchecksum"?: string & "yes" | "no" | *"yes"

    "rdbcompression"?: string & "yes" | "no" | *"yes"

    // only in 8.1
    "rdma-bind"?: string

    // only in 8.1
    "rdma-completion-vector"?: int | *-1

    // only in 8.1
    "rdma-port"?: int | *0

    // only in 8.1
    "rdma-rx-size"?: int

    "repl-backlog-size"?: int | *1048576

    "repl-backlog-ttl"?: int | *3600

    "repl-disable-tcp-nodelay"?: string & "yes" | "no" | *"no"

    "repl-diskless-load"?: string & "disabled" | "swapdb" | "on-empty-db" | *"disabled"

    "repl-diskless-sync"?: string & "yes" | "no" | *"yes"

    "repl-diskless-sync-delay"?: int | *5

    "repl-diskless-sync-max-replicas"?: int | *0

    // legacy alias: repl-ping-slave-period
    "repl-ping-replica-period"?: int | *10

    "repl-timeout"?: int | *60

    "replica-ignore-disk-write-errors"?: string & "yes" | "no" | *"no"

    // legacy alias: slave-ignore-maxmemory
    "replica-ignore-maxmemory"?: string & "yes" | "no" | *"yes"

    // legacy alias: slave-lazy-flush
    "replica-lazy-flush"?: string & "yes" | "no"

    // legacy alias: slave-priority
    "replica-priority"?: int | *100

    // legacy alias: slave-read-only
    "replica-read-only"?: string & "yes" | "no" | *"yes"

    // legacy alias: slave-serve-stale-data
    "replica-serve-stale-data"?: string & "yes" | "no" | *"yes"

    "req-res-logfile"?: string

    "save"?: string

    // legacy alias: server_cpulist
    "server-cpulist"?: string

    "set-max-intset-entries"?: int & >=0 & <=500000000 | *512

    "set-max-listpack-entries"?: int | *128

    "set-max-listpack-value"?: int | *64

    "set-proc-title"?: string & "yes" | "no" | *"yes"

    "shutdown-on-sigint"?: string

    "shutdown-on-sigterm"?: string

    "shutdown-timeout"?: int | *10

    // only in 8.0
    "slowlog-log-slower-than"?: int | *10000

    // only in 8.0
    "slowlog-max-len"?: int | *128

    "socket-mark-id"?: int | *0

    "stop-writes-on-bgsave-error"?: string & "yes" | "no" | *"yes"

    "stream-node-max-bytes"?: int | *4096

    "stream-node-max-entries"?: int | *100

    "tcp-backlog"?: int & >=0 | *511

    "tcp-keepalive"?: int | *300

    "timeout"?: int | *0

    "tracking-table-max-keys"?: int & >=1 & <=100000000 | *1000000

    "unixsocketgroup"?: string

    "use-exit-on-panic"?: string & "yes" | "no" | *"no"

    "watchdog-period"?: int | *0

    // legacy alias: zset-max-ziplist-entries
    "zset-max-listpack-entries"?: int | *128

    // legacy alias: zset-max-ziplist-value
    "zset-max-listpack-value"?: int | *64
	...
}

configuration: #ValkeyParameter & {
}
