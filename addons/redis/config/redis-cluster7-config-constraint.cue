#RedisParameter: {

	"acllog-max-len": int & >=1 & <=10000 | *128

	"acl-pubsub-default"?: string & "resetchannels" | "allchannels"

	activedefrag?: string & "yes" | "no"

	"active-defrag-cycle-max": int & >=1 & <=75 | *75

	"active-defrag-cycle-min": int & >=1 & <=75 | *5

	"active-defrag-ignore-bytes": int | *104857600

	"active-defrag-max-scan-fields": int & >=1 & <=1000000 | *1000

	"active-defrag-threshold-lower": int & >=1 & <=100 | *10

	"active-defrag-threshold-upper": int & >=1 & <=100 | *100

	"active-expire-effort": int & >=1 & <=10 | *1

	appendfsync?: string & "always" | "everysec" | "no"

	appendonly?: string & "yes" | "no"

	"cluster-enabled"?: string & "yes" | "no"

	"cluster-allow-replica-migration"?: string & "yes" | "no"

	"cluster-require-full-coverage"?: string & "yes" | "no"

	"cluster-allow-reads-when-down"?: string & "yes" | "no"

	"cluster-node-timeout": int | *0

	"cluster-replica-validity-factor": int | *0

	"client-output-buffer-limit normal": string | *"0 0 0"

	"client-output-buffer-limit replica": string | *"256mb 64mb 60"

	"client-output-buffer-limit pubsub": string | *"32mb 8mb 60"

	"client-query-buffer-limit": int & >=1048576 & <=1073741824 | *1073741824

	"close-on-replica-write"?: string & "yes" | "no"

	"cluster-allow-pubsubshard-when-down"?: string & "yes" | "no"

	"cluster-preferred-endpoint-type"?: string & "tls-dynamic" | "ip"

	databases: int & >=1 & <=10000 | *16

	"hash-max-listpack-entries": int | *512

	"hash-max-listpack-value": int | *64

	"hll-sparse-max-bytes": int & >=1 & <=16000 | *3000

	"latency-tracking"?: string & "yes" | "no"

	"lazyfree-lazy-eviction"?: string & "yes" | "no"

	"lazyfree-lazy-expire"?: string & "yes" | "no"

	"lazyfree-lazy-server-del"?: string & "yes" | "no"

	"lazyfree-lazy-user-del"?: string & "yes" | "no"

	"lfu-decay-time": int | *1

	"lfu-log-factor": int | *10

	"list-compress-depth": int | *0

	"list-max-listpack-size": int | *-2

	"lua-time-limit": int & 5000 | *5000

	maxclients: int & >=1 & <=65000 | *65000

	"maxmemory-policy"?: string & "volatile-lru" | "allkeys-lru" | "volatile-lfu" | "allkeys-lfu" | "volatile-random" | "allkeys-random" | "volatile-ttl" | "noeviction"

	"maxmemory-samples": int | *3

	"maxmemory"?: int

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

	"tcp-keepalive": int | *300

	timeout: int | *0

	"tracking-table-max-keys": int & >=1 & <=100000000 | *1000000

	"zset-max-listpack-entries": int | *128

	"zset-max-listpack-value": int | *64

	"protected-mode"?: string & "yes" | "no"

	"enable-debug-command"?: string & "yes" | "no" | "local"

	"io-threads": int & >=2 & <=8 | *4

	"io-threads-do-reads"?: string & "yes" | "no"
     // In some cases redis will emit warnings and even refuse to start if it detects that the system is in bad state, it is possible to suppress these warnings
     // by setting the following config which takes a space delimited list of warnings to suppress, example: "ARM64-COW-BUG"
	 "ignore-warnings": string & "ARM64-COW-BUG"

     // Set bgsave child process to cpu affinity 1,10,11, example: "1,10-11"
	 "bgsave_cpulist": string

     // Set aof rewrite child process to cpu affinity 8,9,10,11, example: "8-11"
     "aof_rewrite_cpulist": string

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

     // MAXMEMORY POLICY: how Redis will select what to remove when maxmemory
     // is reached. You can select one from the following behaviors:
     // volatile-lru -> Evict using approximated LRU, only keys with an expire set.
     // allkeys-lru -> Evict any key using approximated LRU.
     // volatile-lfu -> Evict using approximated LFU, only keys with an expire set.
     // allkeys-lfu -> Evict any key using approximated LFU.
     // volatile-random -> Remove a random key having an expire set.
     // allkeys-random -> Remove a random key, any key.
     // volatile-ttl -> Remove the key with the nearest expire time (minor TTL)
     // noeviction -> Don't evict anything, just return an error on write operations.
     // LRU means Least Recently Used
     // LFU means Least Frequently Used
     // Both LRU, LFU and volatile-ttl are implemented using approximated
     // randomized algorithms.
     // Note: with any of the above policies, when there are no suitable keys for
     // eviction, Redis will return an error on write operations that require
     // more memory. These are usually commands that create new keys, add data or
     // modify existing keys. A few examples are: SET, INCR, HSET, LPUSH, SUNIONSTORE,
     // SORT (due to the STORE argument), and EXEC (if the transaction includes any
     // command that requires memory).
     "maxmemory-policy": string & "volatile-lru" | "allkeys-lru" | "volatile-lfu" | "allkeys-lfu" | "volatile-random" | "allkeys-random" | "volatile-ttl" | "noeviction" | *"volatile-lru"

     // LRU, LFU and minimal TTL algorithms are not precise algorithms but approximated
     // algorithms (in order to save memory), so you can tune it for speed or
     // accuracy. By default Redis will check five keys and pick the one that was
     // used least recently, you can change the sample size using the following
     // configuration directive.
     // The default of 5 produces good enough results. 10 Approximates very closely
     // true LRU but costs more CPU. 3 is faster but not very accurate.
     "maxmemory-samples": int | *5

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

     "lazyfree-lazy-user-del": string & "yes" | "no" | *"no"

     // FLUSHDB, FLUSHALL, SCRIPT FLUSH and FUNCTION FLUSH support both asynchronous and synchronous
     // deletion, which can be controlled by passing the [SYNC|ASYNC] flags into the
     // commands. When neither flag is passed, this directive will be used to determine
     // if the data should be deleted asynchronously.
     "lazyfree-lazy-user-flush": string & "yes" | "no" | *"no"

     "auto-aof-rewrite-percentage": int | *100

     "auto-aof-rewrite-min-size": string | *"64mb"

     "lua-time-limit": int | *5000

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

    // Set redis server/io threads to cpu affinity 0,2,4,6:
    // server_cpulist: "0-7:2"
    server_cpulist: string | *""

    // Set bio threads to cpu affinity 1,3:
    // bio_cpulist 1,3
    bio_cpulist: string

    // Jemalloc background thread for purging will be enabled by default
    "jemalloc-bg-thread": string & "yes" | "no" | *"yes"

    "repl-ping-replica-period": int | *10

    "repl-timeout": int | *60

    "repl-disable-tcp-nodelay": string & "yes" | "no" | *"no"

    "replica-priority": int | *100

    "tcp-backlog": int & >=0 | *511

    "daemonize": string & "yes" | "no" | *"no"

    "always-show-logo": string & "yes" | "no" | *yes

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
