//Copyright (C) 2022-2023 ApeCloud Co., Ltd
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

#RedisParameter: {

	"acllog-max-len": int & >=1 & <=10000 | *128

	"acl-pubsub-default"?: string & "resetchannels" | "allchannels"

	activedefrag?: string & "yes" | "no"

	"active-defrag-cycle-max": int & >=1 & <=75 | *25

	"active-defrag-cycle-min": int & >=1 & <=75 | *1

	"active-defrag-ignore-bytes": int | *104857600

	"active-defrag-max-scan-fields": int & >=1 & <=1000000 | *1000

	"active-defrag-threshold-lower": int & >=1 & <=100 | *10

	"active-defrag-threshold-upper": int & >=1 & <=100 | *100

	"active-expire-effort": int & >=1 & <=10 | *1

	appendfsync?: string & "always" | "everysec" | "no"

	appendonly?: string & "yes" | "no"

	"aof-timestamp-enabled"?: string & "yes" | "no"

	"client-output-buffer-limit normal": string | *"0 0 0"

	"client-output-buffer-limit replica": string | *"256mb 64mb 60"

	"client-output-buffer-limit pubsub": string | *"32mb 8mb 60"

	"client-query-buffer-limit": int & >=1048576 & <=1073741824 | *1073741824

	"close-on-replica-write"?: string & "yes" | "no"

	"cluster-allow-pubsubshard-when-down"?: string & "yes" | "no"

	"cluster-allow-reads-when-down"?: string & "yes" | "no"

	"cluster-enabled"?: string & "yes" | "no"

	"cluster-preferred-endpoint-type"?: string & "tls-dynamic" | "ip"

	"cluster-require-full-coverage"?: string & "yes" | "no"

	databases: int & >=1 & <=10000 | *16

	"hash-max-listpack-entries": int | *512

	"hash-max-listpack-value": int | *64

	"hll-sparse-max-bytes": int & >=1 & <=16000 | *3000

	"latency-tracking"?: string & "yes" | "no"

	"lfu-decay-time": int | *1

	"lfu-log-factor": int | *10

	"list-compress-depth": int | *0

	"list-max-listpack-size": int | *-2

	maxclients: int & >=1 & <=65000 | *65000

	maxmemory?: int

	"min-replicas-max-lag": int | *10

	"min-replicas-to-write": int | *0

	"notify-keyspace-events"?: string

	"proto-max-bulk-len": int & >=1048576 & <=536870912 | *536870912

	"rename-commands"?: string & "APPEND" | "BITCOUNT" | "BITFIELD" | "BITOP" | "BITPOS" | "BLPOP" | "BRPOP" | "BRPOPLPUSH" | "BZPOPMIN" | "BZPOPMAX" | "CLIENT" | "COMMAND" | "DBSIZE" | "DECR" | "DECRBY" | "DEL" | "DISCARD" | "DUMP" | "ECHO" | "EVAL" | "EVALSHA" | "EXEC" | "EXISTS" | "EXPIRE" | "EXPIREAT" | "FLUSHALL" | "FLUSHDB" | "GEOADD" | "GEOHASH" | "GEOPOS" | "GEODIST" | "GEORADIUS" | "GEORADIUSBYMEMBER" | "GET" | "GETBIT" | "GETRANGE" | "GETSET" | "HDEL" | "HEXISTS" | "HGET" | "HGETALL" | "HINCRBY" | "HINCRBYFLOAT" | "HKEYS" | "HLEN" | "HMGET" | "HMSET" | "HSET" | "HSETNX" | "HSTRLEN" | "HVALS" | "INCR" | "INCRBY" | "INCRBYFLOAT" | "INFO" | "KEYS" | "LASTSAVE" | "LINDEX" | "LINSERT" | "LLEN" | "LPOP" | "LPUSH" | "LPUSHX" | "LRANGE" | "LREM" | "LSET" | "LTRIM" | "MEMORY" | "MGET" | "MONITOR" | "MOVE" | "MSET" | "MSETNX" | "MULTI" | "OBJECT" | "PERSIST" | "PEXPIRE" | "PEXPIREAT" | "PFADD" | "PFCOUNT" | "PFMERGE" | "PING" | "PSETEX" | "PSUBSCRIBE" | "PUBSUB" | "PTTL" | "PUBLISH" | "PUNSUBSCRIBE" | "RANDOMKEY" | "READONLY" | "READWRITE" | "RENAME" | "RENAMENX" | "RESTORE" | "ROLE" | "RPOP" | "RPOPLPUSH" | "RPUSH" | "RPUSHX" | "SADD" | "SCARD" | "SCRIPT" | "SDIFF" | "SDIFFSTORE" | "SELECT" | "SET" | "SETBIT" | "SETEX" | "SETNX" | "SETRANGE" | "SINTER" | "SINTERSTORE" | "SISMEMBER" | "SLOWLOG" | "SMEMBERS" | "SMOVE" | "SORT" | "SPOP" | "SRANDMEMBER" | "SREM" | "STRLEN" | "SUBSCRIBE" | "SUNION" | "SUNIONSTORE" | "SWAPDB" | "TIME" | "TOUCH" | "TTL" | "TYPE" | "UNSUBSCRIBE" | "UNLINK" | "UNWATCH" | "WAIT" | "WATCH" | "ZADD" | "ZCARD" | "ZCOUNT" | "ZINCRBY" | "ZINTERSTORE" | "ZLEXCOUNT" | "ZPOPMAX" | "ZPOPMIN" | "ZRANGE" | "ZRANGEBYLEX" | "ZREVRANGEBYLEX" | "ZRANGEBYSCORE" | "ZRANK" | "ZREM" | "ZREMRANGEBYLEX" | "ZREMRANGEBYRANK" | "ZREMRANGEBYSCORE" | "ZREVRANGE" | "ZREVRANGEBYSCORE" | "ZREVRANK" | "ZSCORE" | "ZUNIONSTORE" | "SCAN" | "SSCAN" | "HSCAN" | "ZSCAN" | "XINFO" | "XADD" | "XTRIM" | "XDEL" | "XRANGE" | "XREVRANGE" | "XLEN" | "XREAD" | "XGROUP" | "XREADGROUP" | "XACK" | "XCLAIM" | "XPENDING" | "GEORADIUS_RO" | "GEORADIUSBYMEMBER_RO" | "LOLWUT" | "XSETID" | "SUBSTR" | "BITFIELD_RO" | "ACL" | "STRALGO"

	"repl-backlog-size": int | *1048576

	"repl-backlog-ttl": int | *3600

	"replica-allow-chaining"?: string & "yes" | "no"

	"replica-ignore-maxmemory"?: string & "yes" | "no"

	"replica-lazy-flush"?: string & "yes" | "no"

	"reserved-memory-percent": int & >=0 & <=100 | *25

	"set-max-intset-entries": int & >=0 & <=500000000 | *512

	"slowlog-log-slower-than": int | *10000

	"slowlog-max-len": int | *128

	"stream-node-max-bytes": int | *4096

	"stream-node-max-entries": int | *100

    // TCP keepalive.
    // If non-zero, use SO_KEEPALIVE to send TCP ACKs to clients in absence
    // of communication. This is useful for two reasons:
    // 1) Detect dead peers.
    // 2) Force network equipment in the middle to consider the connection to be
    //    alive.
    // On Linux, the specified value (in seconds) is the period used to send ACKs.
    // Note that to close the connection the double of the time is needed.
    // On other kernels the period depends on the kernel configuration.
    //
    // A reasonable value for this option is 300 seconds, which is the new
    // Redis default starting with Redis 3.2.1.
	"tcp-keepalive": int | *300

    // Close the connection after a client is idle for N seconds (0 to disable)
	timeout: int | *0

	"tracking-table-max-keys": int & >=1 & <=100000000 | *1000000

    // only supported when version >= 7.2
	"zset-max-listpack-entries": int | *128

	"zset-max-listpack-value": int | *64

	"protected-mode"?: string & "yes" | "no" | *"yes"

    // no    - Block for any connection (remain immutable)
    // yes   - Allow for any connection (no protection)
    // local - Allow only for local connections. Ones originating from the
    // IPv4 address (127.0.0.1), IPv6 address (::1) or Unix domain sockets.
	"enable-debug-command"?: string & "yes" | "no" | "local"

	"io-threads": int & >=2 & <=8 | *4

	"io-threads-do-reads"?: string & "yes" | "no"

    // In some cases redis will emit warnings and even refuse to start if it detects that the system is in bad state, it is possible to suppress these warnings
    // by setting the following config which takes a space delimited list of warnings to suppress, example: "ARM64-COW-BUG"
	"ignore-warnings": string & "ARM64-COW-BUG"

    // Set bgsave child process to cpu affinity 1,10,11, example: "1,10-11"
	"bgsave_cpulist"?: string

    // Set aof rewrite child process to cpu affinity 8,9,10,11, example: "8-11"
    "aof_rewrite_cpulist"?: string

    // Specify the server verbosity level.
    // This can be one of:
    // debug (a lot of information, useful for development/testing)
    // verbose (many rarely useful info, but not a mess like the debug level)
    // notice (moderately verbose, what you want in production probably)
    // warning (only very important / critical messages are logged)
    // nothing (nothing is logged)
    loglevel: string & "debug" | "verbose" | "notice" | "warning" | "nothing" | *"notice"

    // To disable the built in crash log, which will possibly produce cleaner core
    // dumps when they are needed, uncomment the following:
    "crash-log-enabled": string & "no" | "yes" | *"yes"

    // To disable the fast memory check that's run as part of the crash log, which
    // will possibly let redis terminate sooner, uncomment the following:
    "crash-memcheck-enabled": string & "no" | "yes" | *"yes"

    // Set the number of databases. The default database is DB 0, you can select
    // a different one on a per-connection basis using SELECT <dbid> where
    // dbid is a number between 0 and 'databases'-1
    databases: int | *16

    // Set the local environment which is used for string comparison operations, and
    // also affect the performance of Lua scripts. Empty String indicates the locale
    // is derived from the environment variables.
    "locale-collate": string | *""

    // Save the DB to disk.
    // save <seconds> <changes> [<seconds> <changes> ...]
    // Redis will save the DB if the given number of seconds elapsed and it
    // surpassed the given number of write operations against the DB.
    // Snapshotting can be completely disabled with a single empty string argument
    // as in following example:
    // save ""
    // Unless specified otherwise, by default Redis will save the DB:
    //   * After 3600 seconds (an hour) if at least 1 change was performed
    //   * After 300 seconds (5 minutes) if at least 100 changes were performed
    //   * After 60 seconds if at least 10000 changes were performed
    save: string | *"3600 1 300 100 60 10000"

    // By default Redis will stop accepting writes if RDB snapshots are enabled
    // (at least one save point) and the latest background save failed.
    // This will make the user aware (in a hard way) that data is not persisting
    // on disk properly, otherwise chances are that no one will notice and some
    // disaster will happen.
    // If the background saving process will start working again Redis will
    // automatically allow writes again.
    // However if you have setup your proper monitoring of the Redis server
    // and persistence, you may want to disable this feature so that Redis will
    // continue to work as usual even if there are problems with disk,
    // permissions, and so forth.
    "stop-writes-on-bgsave-error": string & "yes" | "no" | *"yes"

    // Eviction processing is designed to function well with the default setting.
    // If there is an unusually large amount of write traffic, this value may need to
    // be increased.  Decreasing this value may reduce latency at the risk of
    // eviction processing effectiveness
    //   0 = minimum latency, 10 = default, 100 = process without regard to latency
    "maxmemory-eviction-tenacity": int & >=0 & <=100 | *10

    // Starting from Redis 5, by default a replica will ignore its maxmemory setting
    // (unless it is promoted to master after a failover or manually). It means
    // that the eviction of keys will be just handled by the master, sending the
    // DEL commands to the replica as keys evict in the master side.
    // This behavior ensures that masters and replicas stay consistent, and is usually
    // what you want, however if your replica is writable, or you want the replica
    // to have a different memory setting, and you are sure all the writes performed
    // to the replica are idempotent, then you may change this default (but be sure
    // to understand what you are doing).
    // Note that since the replica by default does not evict, it may end using more
    // memory than the one set via maxmemory (there are certain buffers that may
    // be larger on the replica, or data structures may sometimes take more memory
    // and so forth). So make sure you monitor your replicas and make sure they
    // have enough memory to never hit a real out-of-memory condition before the
    // master hits the configured maxmemory setting.
    "replica-ignore-maxmemory": string & "yes" | "no" | *"yes"

    // Redis reclaims expired keys in two ways: upon access when those keys are
    // found to be expired, and also in background, in what is called the
    // "active expire key". The key space is slowly and interactively scanned
    // looking for expired keys to reclaim, so that it is possible to free memory
    // of keys that are expired and will never be accessed again in a short time.
    // The default effort of the expire cycle will try to avoid having more than
    // ten percent of expired keys still in memory, and will try to avoid consuming
    // more than 25% of total memory and to add latency to the system. However
    // it is possible to increase the expire "effort" that is normally set to
    // "1", to a greater value, up to the value "10". At its maximum value the
    // system will use more CPU, longer cycles (and technically may introduce
    // more latency), and will tolerate less already expired keys still present
    // in the system. It's a tradeoff between memory, CPU and latency.
    "active-expire-effort": int & >=1 & <=10 | *1

    "lazyfree-lazy-eviction": string & "yes" | "no" | *"no"

    "lazyfree-lazy-expire": string & "yes" | "no" | *"no"

    "lazyfree-lazy-server-del": string & "yes" | "no" | *"no"

    "lazyfree-lazy-flush": string & "yes" | "no" | *"no"

    "lazyfree-lazy-user-del": string & "yes" | "no" | *"no"

    // FLUSHDB, FLUSHALL, SCRIPT FLUSH and FUNCTION FLUSH support both asynchronous and synchronous
    // deletion, which can be controlled by passing the [SYNC|ASYNC] flags into the
    // commands. When neither flag is passed, this directive will be used to determine
    // if the data should be deleted asynchronously.
    "lazyfree-lazy-user-flush": string & "yes" | "no" | *"no"

    "auto-aof-rewrite-percentage": int | *100

    "auto-aof-rewrite-min-size": string | *"64mb"

    "busy-reply-threshold": int | *5000

    // By default latency monitoring is disabled since it is mostly not needed
    // if you don't have latency issues, and collecting data has a performance
    // impact, that while very small, can be measured under big load. Latency
    // monitoring can easily be enabled at runtime using the command
    // "CONFIG SET latency-monitor-threshold <milliseconds>" if needed.
    "latency-monitor-threshold": int | *0

    // By default the exported latency percentiles via the INFO latencystats command
    // are the p50, p99, and p999.
    "latency-tracking-info-percentiles": string | *"50 99 999"

    // Redis calls an internal function to perform many background tasks, like
    // closing connections of clients in timeout, purging expired keys that are
    // never requested, and so forth.
    // Not all tasks are performed with the same frequency, but Redis checks for
    // tasks to perform according to the specified "hz" value.
    // By default "hz" is set to 10. Raising the value will use more CPU when
    // Redis is idle, but at the same time will make Redis more responsive when
    // there are many keys expiring at the same time, and timeouts may be
    // handled with more precision.
    // The range is between 1 and 500, however a value over 100 is usually not
    // a good idea. Most users should use the default of 10 and raise this up to
    // 100 only in environments where very low latency is required.
    hz: int | *10

    // When dynamic HZ is enabled, the actual configured HZ will be used
    // as a baseline, but multiples of the configured HZ value will be actually
    // used as needed once more clients are connected. In this way an idle
    // instance will use very little CPU time while a busy instance will be
    // more responsive.
    "dynamic-hz": string & "yes" | "no" | *"yes"

    // When a child rewrites the AOF file, if the following option is enabled
    // the file will be fsync-ed every 4 MB of data generated. This is useful
    // in order to commit the file to the disk more incrementally and avoid
    // big latency spikes.
    "aof-rewrite-incremental-fsync": string & "yes" | "no" | *"yes"

    // When redis saves RDB file, if the following option is enabled
    // the file will be fsync-ed every 4 MB of data generated. This is useful
    // in order to commit the file to the disk more incrementally and avoid
    // big latency spikes.
    "rdb-save-incremental-fsync": string & "yes" | "no" | *"yes"

    // A memory value can be used for the client eviction threshold,
    // for example: 1g or 5%
    "maxmemory-clients": string | *"0"

    // no    - Block for any connection (remain immutable)
    // yes   - Allow for any connection (no protection)
    // local - Allow only for local connections. Ones originating from the
    // IPv4 address (127.0.0.1), IPv6 address (::1) or Unix domain sockets.
    "enable-protected-configs": string & "yes" | "no" | "local" | *"no"

    // no    - Block for any connection (remain immutable)
    // yes   - Allow for any connection (no protection)
    // local - Allow only for local connections. Ones originating from the
    // IPv4 address (127.0.0.1), IPv6 address (::1) or Unix domain sockets.
    "enable-module-command": string & "yes" | "no" | "local" | *"no"

    // Set redis server/io threads to cpu affinity 0,2,4,6:
    // server_cpulist: "0-7:2"
    server_cpulist: string | *""

    // Set bio threads to cpu affinity 1,3:
    // bio_cpulist 1,3
    bio_cpulist?: string

    // Jemalloc background thread for purging will be enabled by default
    "jemalloc-bg-thread": string & "yes" | "no" | *"yes"

    "repl-ping-replica-period": int | *10

    "repl-timeout": int | *60

    "repl-disable-tcp-nodelay": string & "yes" | "no" | *"no"

    "replica-priority": int | *100

    "propagation-error-behavior": string | *"ignore"

    "replica-ignore-disk-write-errors": string & "yes" | "no" | *"no"
    
    // Keep numeric ranges in numeric tree parent nodes of leafs for `x` generations.
    // numeric, valid range: [0, 2], default: 0
    "search-_numeric-ranges-parents": int & >=0 & <=2 | *0
    
    // The number of iterations to run while performing background indexing
    // before we call usleep(1) (sleep for 1 micro-second) and make sure that we
    // allow redis to process other commands.
    // numeric, valid range: [1, UINT32_MAX], default: 100
    "search-bg-index-sleep-gap": int & >=1 & <=4294967295 | *100
    
    // The default dialect used in search queries.
    // numeric, valid range: [1, 4], default: 1
    "search-default-dialect": int & >=1 & <=4 | *1
    
    // the fork gc will only start to clean when the number of not cleaned document
    // will exceed this threshold.
    // numeric, valid range: [1, LLONG_MAX], default: 100
    "search-fork-gc-clean-threshold": int & >=1 & <=9223372036854775807 | *100
    
    // interval (in seconds) in which to retry running the forkgc after failure.
    // numeric, valid range: [1, LLONG_MAX], default: 5
    "search-fork-gc-retry-interval": int & >=1 & <=9223372036854775807 | *5
    
    // interval (in seconds) in which to run the fork gc (relevant only when fork
    // gc is used).
    // numeric, valid range: [1, LLONG_MAX], default: 30
    "search-fork-gc-run-interval": int & >=1 & <=9223372036854775807 | *30
    
    // the amount of seconds for the fork GC to sleep before exiting.
    // numeric, valid range: [0, LLONG_MAX], default: 0
    "search-fork-gc-sleep-before-exit": int & >=0 & <=9223372036854775807 | *0
    
    // Scan this many documents at a time during every GC iteration.
    // numeric, valid range: [1, LLONG_MAX], default: 100
    "search-gc-scan-size": int & >=1 & <=9223372036854775807 | *100
    
    // Max number of cursors for a given index that can be opened inside of a shard.
    // numeric, valid range: [0, LLONG_MAX], default: 128
    "search-index-cursor-limit": int & >=0 & <=9223372036854775807 | *128
    
    // Maximum number of results from ft.aggregate command.
    // numeric, valid range: [0, (1ULL << 31)], default: 1ULL << 31
    "search-max-aggregate-results": int & >=0 & <=2147483648 | *2147483648
    
    // Maximum prefix expansions to be used in a query.
    // numeric, valid range: [1, LLONG_MAX], default: 200
    "search-max-prefix-expansions": int & >=1 & <=9223372036854775807 | *200
    
    // Maximum runtime document table size (for this process).
    // numeric, valid range: [1, 100000000], default: 1000000
    "search-max-doctablesize": int & >=1 & <=100000000 | *1000000
    
    // max idle time allowed to be set for cursor, setting it high might cause
    // high memory consumption.
    // numeric, valid range: [1, LLONG_MAX], default: 300000
    "search-cursor-max-idle": int & >=1 & <=9223372036854775807 | *300000
    
    // Maximum number of results from ft.search command.
    // numeric, valid range: [0, 1ULL << 31], default: 1000000
    "search-max-search-results": int & >=0 & <=2147483648 | *1000000
    
    // Number of worker threads to use for background tasks when the server is
    // in an operation event.
    // numeric, valid range: [1, 16], default: 4
    "search-min-operation-workers": int & >=1 & <=16 | *4
    
    // Minimum length of term to be considered for phonetic matching.
    // numeric, valid range: [1, LLONG_MAX], default: 3
    "search-min-phonetic-term-len": int & >=1 & <=9223372036854775807 | *3
    
    // the minimum prefix for expansions (`*`).
    // numeric, valid range: [1, LLONG_MAX], default: 2
    "search-min-prefix": int & >=1 & <=9223372036854775807 | *2
    
    // the minimum word length to stem.
    // numeric, valid range: [2, UINT32_MAX], default: 4
    "search-min-stem-len": int & >=2 & <=4294967295 | *4
    
    // Delta used to increase positional offsets between array
    // slots for multi text values.
    // Can control the level of separation between phrases in different
    // array slots (related to the SLOP parameter of ft.search command)"
    // numeric, valid range: [1, UINT32_MAX], default: 100
    "search-multi-text-slop": int | >= 1 & <= 4294967295 | *100
    
    // Used for setting the buffer limit threshold for vector similarity tiered
    // HNSW index, so that if we are using WORKERS for indexing, and the
    // number of vectors waiting in the buffer to be indexed exceeds this limit,
    // we insert new vectors directly into HNSW.
    // numeric, valid range: [0, LLONG_MAX], default: 1024
    "search-tiered-hnsw-buffer-limit": int & >=0 & <=9223372036854775807 | *1024
    
    // Query timeout.
    // numeric, valid range: [1, LLONG_MAX], default: 500
    "search-timeout": int & >=1 & <=9223372036854775807 | *500
    
    // minimum number of iterators in a union from which the iterator will
    // will switch to heap-based implementation.
    // numeric, valid range: [1, LLONG_MAX], default: 20
    // switch to heap based implementation.
    "search-union-iterator-heap": int & >=1 & <=9223372036854775807 | *20
    
    // The maximum memory resize for vector similarity indexes (in bytes).
    // numeric, valid range: [0, UINT32_MAX], default: 0
    "search-vss-max-resize": int | *0
    
    // Number of worker threads to use for query processing and background tasks.
    // numeric, valid range: [0, 16], default: 0
    // This configuration also affects the number of connections per shard.
    "search-workers": int & >=0 & <=16 | *0
    
    // The number of high priority tasks to be executed at any given time by the
    // worker thread pool, before executing low priority tasks. After this number
    // of high priority tasks are being executed, the worker thread pool will
    // execute high and low priority tasks alternately.
    // numeric, valid range: [0, LLONG_MAX], default: 1
    "search-workers-priority-bias-threshold": int & >=0 & <=9223372036854775807 | *1
    
    // Load extension scoring/expansion module. Immutable.
    // string, default: ""
    "search-ext-load": string | *""
    
    // Path to Chinese dictionary configuration file (for Chinese tokenization). Immutable.
    // string, default: ""
    "search-friso-ini": string | *""
    
    // Action to perform when search timeout is exceeded (choose RETURN or FAIL).
    // enum, valid values: ["return", "fail"], default: "fail"
    "search-on-timeout": string & "return" | "fail" | *"fail"
    
    // Determine whether some index resources are free on a second thread.
    // bool, default: yes
    "search-_free-resource-on-thread": string & "yes" | "no" | *"yes"
    
    // Enable legacy compression of double to float.
    // bool, default: no
    "search-_numeric-compress": string & "yes" | "no" | *"no"
    
    // Disable print of time for ft.profile. For testing only.
    // bool, default: yes
    "search-_print-profile-clock": string & "yes" | "no" | *"yes"
    
    // Intersection iterator orders the children iterators by their relative estimated
    // number of results in ascending order, so that if we see first iterators with
    // a lower count of results we will skip a larger number of results, which
    // translates into faster iteration. If this flag is set, we use this
    // optimization in a way where union iterators are being factorize by the number
    // of their own children, so that we sort by the number of children times the
    // overall estimated number of results instead.
    // bool, default: no
    "search-_prioritize-intersect-union-children": string & "yes" | "no" | *"no"
    
    // Set to run without memory pools.
    // bool, default: no
    "search-no-mem-pools": string & "yes" | "no" | *"no"
    
    // Disable garbage collection (for this process).
    // bool, default: no
    "search-no-gc": string & "yes" | "no" | *"no"
    
    // Enable commands filter which optimize indexing on partial hash updates.
    // bool, default: no
    "search-partial-indexed-docs": string & "yes" | "no" | *"no"
    
    // Disable compression for DocID inverted index. Boost CPU performance.
    // bool, default: no
    "search-raw-docid-encoding": string & "yes" | "no" | *"no"
    
    // Number of search threads in the coordinator thread pool.
    // numeric, valid range: [1, LLONG_MAX], default: 20
    "search-threads": int & >=1 & <=9223372036854775807 | *20
    
    // Timeout for topology validation (in milliseconds). After this timeout,
    // any pending requests will be processed, even if the topology is not fully connected.
    // numeric, valid range: [0, LLONG_MAX], default: 30000
    "search-topology-validation-timeout": int & >=0 & <=9223372036854775807 | *30000

    // The maximal number of per-shard threads for cross-key queries when using cluster mode
    // (TS.MRANGE, TS.MREVRANGE, TS.MGET, and TS.QUERYINDEX).
    // Note: increasing this value may either increase or decrease the performance.
    // integer, valid range: [1..16], default: 3
    // This is a load-time configuration parameter.
    "ts-num-threads": int & >=1 & <=16 | *3
    
    // Default compaction rules for newly created key with TS.ADD, TS.INCRBY, and TS.DECRBY.
    // Has no effect on keys created with TS.CREATE.
    // This default value is applied to each new time series upon its creation.
    // string, see documentation for rules format, default: no compaction rules
    "ts-compaction-policy": string | *""
    
    // Default chunk encoding for automatically-created compacted time series.
    // This default value is applied to each new compacted time series automatically
    // created when ts-compaction-policy is specified.
    // valid values: COMPRESSED, UNCOMPRESSED, default: COMPRESSED
    "ts-encoding": string & "COMPRESSED" | "UNCOMPRESSED" | *"COMPRESSED"
    
    // Default retention period, in milliseconds. 0 means no expiration.
    // This default value is applied to each new time series upon its creation.
    // If ts-compaction-policy is specified - it is overridden for created
    // compactions as specified in ts-compaction-policy.
    // integer, valid range: [0 .. LLONG_MAX], default: 0
    "ts-retention-policy": int & >=0 & <=9223372036854775807 | *0
    
    // Default policy for handling insertion (TS.ADD and TS.MADD) of multiple
    // samples with identical timestamps.
    // This default value is applied to each new time series upon its creation.
    // string, valid values: BLOCK, FIRST, LAST, MIN, MAX, SUM, default: BLOCK
    "ts-duplicate-policy": string & "BLOCK" | "FIRST" | "LAST" | "MIN" | "MAX" | "SUM" | *"BLOCK"
    
    // Default initial allocation size, in bytes, for the data part of each new chunk
    // This default value is applied to each new time series upon its creation.
    // integer, valid range: [48 .. 1048576]; must be a multiple of 8, default: 4096
    "ts-chunk-size-bytes": int & >=48 & <=1048576 | *4096
    
    // Default values for newly created time series.
    // Many sensors report data periodically. Often, the difference between the measured
    // value and the previous measured value is negligible and related to random noise
    // or to measurement accuracy limitations. In such situations it may be preferable
    // not to add the new measurement to the time series.
    // A new sample is considered a duplicate and is ignored if the following conditions are met:
    // - The time series is not a compaction;
    // - The time series' DUPLICATE_POLICY IS LAST;
    // - The sample is added in-order (timestamp >= max_timestamp);
    // - The difference of the current timestamp from the previous timestamp
    //   (timestamp - max_timestamp) is less than or equal to ts-ignore-max-time-diff
    // - The absolute value difference of the current value from the value at the previous maximum timestamp
    //   (abs(value - value_at_max_timestamp) is less than or equal to ts-ignore-max-val-diff.
    // where max_timestamp is the timestamp of the sample with the largest timestamp in the time series,
    // and value_at_max_timestamp is the value at max_timestamp.
    // ts-ignore-max-time-diff: integer, valid range: [0 .. LLONG_MAX], default: 0
    // ts-ignore-max-val-diff: double, Valid range: [0 .. DBL_MAX], default: 0
    "ts-ignore-max-time-diff": int & >=0 & <=9223372036854775807 | *0
    "ts-ignore-max-val-diff": float & >=0 | *0

    // Error ratio
    // The desired probability for false positives.
    // For a false positive rate of 0.1% (1 in 1000) - the value should be 0.001.
    // double, Valid range: (0 .. 1), value greater than 0.25 is treated as 0.25, default: 0.01
    "bf-error-rate": float & >=0 & <=1 | *0.01
    
    // Initial capacity
    // The number of entries intended to be added to the filter.
    // integer, valid range: [1 .. 1GB], default: 100
    "bf-initial-size": int & >=1 & <=1073741824 | *100
    
    // Expansion factor
    // When capacity is reached, an additional sub-filter is created.
    // The size of the new sub-filter is the size of the last sub-filter multiplied
    // by expansion.
    // integer, [0 .. 32768]. 0 is equivalent to NONSCALING. default: 2
    "bf-expansion-factor": int & >=0 & <=32768 | *2

    // Initial capacity
    // A filter will likely not fill up to 100% of its capacity.
    // Make sure to reserve extra capacity if you want to avoid expansions.
    // value is rounded to the next 2^n integer.
    // integer, valid range: [2*cf-bucket-size .. 1GB], default: 1024
    "cf-initial-size": int & >=2 & <=1073741824 | *1024
    
    // Number of items in each bucket
    // The minimal false positive rate is 2/255 ~ 0.78% when bucket size of 1 is used.
    // Larger buckets increase the error rate linearly, but improve the fill rate.
    // integer, valid range: [1 .. 255], default: 2
    "cf-bucket-size": int & >=1 & <=255 | *2
    
    // Maximum iterations
    // Number of attempts to swap items between buckets before declaring filter
    // as full and creating an additional filter.
    // A lower value improves performance. A higher value improves fill rate.
    // integer, Valid range: [1 .. 65535], default: 20
    "cf-max-iterations": int & >=1 & <=65535 | *20
    
    // Expansion factor
    // When a new filter is created, its size is the size of the current filter
    // multiplied by this factor.
    // integer, Valid range: [0 .. 32768], 0 is equivalent to NONSCALING, default: 1
    "cf-expansion-factor": int & >=0 & <=32768 | *1
    
    // Maximum expansions
    // integer, Valid range: [1 .. 65536], default: 32
    "cf-max-expansions": int & >=1 & <=65536 | *32

	...
}

configuration: #RedisParameter & {
}
