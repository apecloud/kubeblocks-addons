#RedisParameter: {

	activedefrag?: string & "yes" | "no"

	"active-defrag-cycle-max": int & >=1 & <=75 | *75

	"active-defrag-cycle-min": int & >=1 & <=75 | *5

	"active-defrag-ignore-bytes": int | *104857600

	"active-defrag-max-scan-fields": int & >=1 & <=1000000 | *1000

	"active-defrag-threshold-lower": int & >=1 & <=100 | *10

	"active-defrag-threshold-upper": int & >=1 & <=100 | *100

	appendfsync?: string & "always" | "everysec" | "no"

	appendonly?: string & "yes" | "no"

	"client-output-buffer-limit normal": string | *"0 0 0"

	"client-output-buffer-limit replica": string | *"256mb 64mb 60"

	"client-output-buffer-limit pubsub": string | *"32mb 8mb 60"

	"client-query-buffer-limit": int & >=1048576 & <=1073741824 | *1073741824

	"close-on-replica-write"?: string & "yes" | "no"

	"cluster-enabled"?: string & "yes" | "no"

	"cluster-require-full-coverage"?: string & "yes" | "no"

	databases: int & >=1 & <=10000 | *16

	"hash-max-listpack-entries": int | *512

	"hash-max-listpack-value": int | *64

	"hll-sparse-max-bytes": int & >=1 & <=16000 | *3000

	"latency-tracking"?: string & "yes" | "no"

	"lazyfree-lazy-eviction"?: string & "yes" | "no"

	"lazyfree-lazy-expire"?: string & "yes" | "no"

	"lazyfree-lazy-server-del"?: string & "yes" | "no"

	"lfu-decay-time": int | *1

	"lfu-log-factor": int | *10

	"list-compress-depth": int | *0

	"list-max-listpack-size": int | *-2

	"lua-time-limit": int & 5000 | *5000

	maxclients: int & >=1 & <=65000 | *65000

	maxmemory?: int

	"maxmemory-policy"?: string & "volatile-lru" | "allkeys-lru" | "volatile-lfu" | "allkeys-lfu" | "volatile-random" | "allkeys-random" | "volatile-ttl" | "noeviction"

	"maxmemory-samples": int | *3

	"min-replicas-max-lag": int | *10

	"min-replicas-to-write": int | *0

	"notify-keyspace-events"?: string

	"proto-max-bulk-len": int & >=1048576 & <=536870912 | *536870912

	"rename-commands"?: string & "APPEND" | "BITCOUNT" | "BITFIELD" | "BITOP" | "BITPOS" | "BLPOP" | "BRPOP" | "BRPOPLPUSH" | "BZPOPMIN" | "BZPOPMAX" | "CLIENT" | "COMMAND" | "DBSIZE" | "DECR" | "DECRBY" | "DEL" | "DISCARD" | "DUMP" | "ECHO" | "EVAL" | "EVALSHA" | "EXEC" | "EXISTS" | "EXPIRE" | "EXPIREAT" | "FLUSHALL" | "FLUSHDB" | "GEOADD" | "GEOHASH" | "GEOPOS" | "GEODIST" | "GEORADIUS" | "GEORADIUSBYMEMBER" | "GET" | "GETBIT" | "GETRANGE" | "GETSET" | "HDEL" | "HEXISTS" | "HGET" | "HGETALL" | "HINCRBY" | "HINCRBYFLOAT" | "HKEYS" | "HLEN" | "HMGET" | "HMSET" | "HSET" | "HSETNX" | "HSTRLEN" | "HVALS" | "INCR" | "INCRBY" | "INCRBYFLOAT" | "INFO" | "KEYS" | "LASTSAVE" | "LINDEX" | "LINSERT" | "LLEN" | "LPOP" | "LPUSH" | "LPUSHX" | "LRANGE" | "LREM" | "LSET" | "LTRIM" | "MEMORY" | "MGET" | "MONITOR" | "MOVE" | "MSET" | "MSETNX" | "MULTI" | "OBJECT" | "PERSIST" | "PEXPIRE" | "PEXPIREAT" | "PFADD" | "PFCOUNT" | "PFMERGE" | "PING" | "PSETEX" | "PSUBSCRIBE" | "PUBSUB" | "PTTL" | "PUBLISH" | "PUNSUBSCRIBE" | "RANDOMKEY" | "READONLY" | "READWRITE" | "RENAME" | "RENAMENX" | "RESTORE" | "ROLE" | "RPOP" | "RPOPLPUSH" | "RPUSH" | "RPUSHX" | "SADD" | "SCARD" | "SCRIPT" | "SDIFF" | "SDIFFSTORE" | "SELECT" | "SET" | "SETBIT" | "SETEX" | "SETNX" | "SETRANGE" | "SINTER" | "SINTERSTORE" | "SISMEMBER" | "SLOWLOG" | "SMEMBERS" | "SMOVE" | "SORT" | "SPOP" | "SRANDMEMBER" | "SREM" | "STRLEN" | "SUBSCRIBE" | "SUNION" | "SUNIONSTORE" | "SWAPDB" | "TIME" | "TOUCH" | "TTL" | "TYPE" | "UNSUBSCRIBE" | "UNLINK" | "UNWATCH" | "WAIT" | "WATCH" | "ZADD" | "ZCARD" | "ZCOUNT" | "ZINCRBY" | "ZINTERSTORE" | "ZLEXCOUNT" | "ZPOPMAX" | "ZPOPMIN" | "ZRANGE" | "ZRANGEBYLEX" | "ZREVRANGEBYLEX" | "ZRANGEBYSCORE" | "ZRANK" | "ZREM" | "ZREMRANGEBYLEX" | "ZREMRANGEBYRANK" | "ZREMRANGEBYSCORE" | "ZREVRANGE" | "ZREVRANGEBYSCORE" | "ZREVRANK" | "ZSCORE" | "ZUNIONSTORE" | "SCAN" | "SSCAN" | "HSCAN" | "ZSCAN" | "XINFO" | "XADD" | "XTRIM" | "XDEL" | "XRANGE" | "XREVRANGE" | "XLEN" | "XREAD" | "XGROUP" | "XREADGROUP" | "XACK" | "XCLAIM" | "XPENDING" | "GEORADIUS_RO" | "GEORADIUSBYMEMBER_RO" | "LOLWUT" | "XSETID" | "SUBSTR" | "BITFIELD_RO" | "STRALGO"

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

	"tcp-keepalive": int | *300

	timeout: int | *0

	"tracking-table-max-keys": int & >=1 & <=100000000 | *1000000

	"zset-max-listpack-entries": int | *128

	"zset-max-listpack-value": int | *64

	"protected-mode"?: string & "yes" | "no"

     // In some cases redis will emit warnings and even refuse to start if it detects that the system is in bad state, it is possible to suppress these warnings
     // by setting the following config which takes a space delimited list of warnings to suppress, example: "ARM64-COW-BUG"
	 "ignore-warnings": string & "ARM64-COW-BUG"

     // Specify the server verbosity level.
     // This can be one of:
     // debug (a lot of information, useful for development/testing)
     // verbose (many rarely useful info, but not a mess like the debug level)
     // notice (moderately verbose, what you want in production probably)
     // warning (only very important / critical messages are logged)
     // nothing (nothing is logged)
     loglevel: string & "debug" | "verbose" | "notice" | "warning" | "nothing" | *"notice"

     // Set the number of databases. The default database is DB 0, you can select
     // a different one on a per-connection basis using SELECT <dbid> where
     // dbid is a number between 0 and 'databases'-1
     databases: int | *16

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

     "lazyfree-lazy-eviction": string & "yes" | "no" | *"no"

     "lazyfree-lazy-expire": string & "yes" | "no" | *"no"

     "lazyfree-lazy-server-del": string & "yes" | "no" | *"no"

     "auto-aof-rewrite-percentage": int | *100

     "auto-aof-rewrite-min-size": string | *"64mb"

     // By default latency monitoring is disabled since it is mostly not needed
     // if you don't have latency issues, and collecting data has a performance
     // impact, that while very small, can be measured under big load. Latency
     // monitoring can easily be enabled at runtime using the command
     // "CONFIG SET latency-monitor-threshold <milliseconds>" if needed.
     "latency-monitor-threshold": int | *0

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

    // Maximum number of set/hash/zset/list fields that will be processed from
    // the main dictionary scan
    "active-defrag-max-scan-fields": int | *1000

    "repl-ping-replica-period": int | *10

    "repl-timeout": int | *60

    "repl-disable-tcp-nodelay": string & "yes" | "no" | *"no"

    "replica-priority": int | *100

    "tcp-backlog": int & >=0 | *511

    "daemonize": string & "yes" | "no" | *"no"

    "always-show-logo": string & "yes" | "no" | *"yes"

    "set-proc-title": string & "yes" | "no" | *"yes"

    "proc-title-template": string | *"{title} {listen-addr} {server-mode}"

    "rdbcompression": string & "yes" | "no" | *"yes"

    "rdbchecksum": string & "yes" | "no" | *"yes"

    "rdb-del-sync-files": string & "yes" | "no" | *"no"

    "replica-serve-stale-data": string & "yes" | "no" | *"yes"

    "replica-read-only": string & "yes" | "no" | *"yes"

    "repl-diskless-sync ":string & "yes" | "no" | *"yes"

    "repl-diskless-sync-delay": int | *5

    "repl-diskless-sync-max-replicas": int | *0

    "repl-diskless-load": string & "disabled" | "disabled" | "on-empty-db" | *"disabled"

    "oom-score-adj": string & "yes" | "no" | "absolute" | "relative" | *"no"

    "oom-score-adj-values": string | *"0 200 800"

    "disable-thp": string & "yes" | "no" | *"yes"

    "no-appendfsync-on-rewrite": string & "yes" | "no" | *"no"

    "aof-load-truncated": string & "yes" | "no" | *"yes"

    "aof-use-rdb-preamble": string & "yes" | "no" | *"yes"

    "activerehashing": string & "yes" | "no" | *"yes"
	...
}

configuration: #RedisParameter & {
}