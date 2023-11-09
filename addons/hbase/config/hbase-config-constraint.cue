// Copyright (C) 2022-2023 ApeCloud Co., Ltd
//
// This file is part of KubeBlocks project
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

// Ref: https://hbase.apache.org/book.html#config.files
#HBaseParameter: {
    // Temporary directory on the local filesystem. Change this setting to point to a location more permanent than '/tmp', the usual resolve for java.io.tmpdir, as the '/tmp' directory is cleared on machine restart.
    "hbase.tmp.dir": string |*"${java.io.tmpdir}/hbase-${user.name}"

    // The directory shared by region servers and into which HBase persists. The URL should be 'fully-qualified' to include the filesystem scheme. For example, to specify the HDFS directory '/hbase' where the HDFS instance’s namenode is running at namenode.example.org on port 9000, set this value to: hdfs://namenode.example.org:9000/hbase. By default, we write to whatever ${hbase.tmp.dir} is set too — usually /tmp — so change this configuration or else all data will be lost on machine restart.
    "hbase.rootdir": string |*"${hbase.tmp.dir}/hbase"

    // The mode the cluster will be in. Possible values are false for standalone mode and true for distributed mode. If false, startup will run all HBase and ZooKeeper daemons together in the one JVM.
    "hbase.cluster.distributed": bool |*false

    // Comma separated list of servers in the ZooKeeper ensemble (This config. should have been named hbase.zookeeper.ensemble). For example, "host1.mydomain.com,host2.mydomain.com,host3.mydomain.com". By default this is set to localhost for local and pseudo-distributed modes of operation. For a fully-distributed setup, this should be set to a full list of ZooKeeper ensemble servers. If HBASE_MANAGES_ZK is set in hbase-env.sh this is the list of servers which hbase will start/stop ZooKeeper on as part of cluster start/stop. Client-side, we will take this list of ensemble members and put it together with the hbase.zookeeper.property.clientPort config. and pass it into zookeeper constructor as the connectString parameter.
    "hbase.zookeeper.quorum": string |*"127.0.0.1"

    // Max sleep time before retry zookeeper operations in milliseconds, a max time is needed here so that sleep time won’t grow unboundedly
    "zookeeper.recovery.retry.maxsleeptime": int & >=0 & <=60000 |*60000

    // Directory on the local filesystem to be used as a local storage.
    "hbase.local.dir": string |*"${hbase.tmp.dir}/local/"

    // The port the HBase Master should bind to.
    "hbase.master.port": int & >=1 & <=65535 |*16000

    // The port for the HBase Master web UI. Set to -1 if you do not want a UI instance run.
    "hbase.master.info.port": int & >=1 & <=65535 |*16010

    // The bind address for the HBase Master web UI
    "hbase.master.info.bindAddress": string |*"0.0.0.0"

    // A comma-separated list of BaseLogCleanerDelegate invoked by the LogsCleaner service. These WAL cleaners are called in order, so put the cleaner that prunes the most files in front. To implement your own BaseLogCleanerDelegate, just put it in HBase’s classpath and add the fully qualified class name here. Always add the above default log cleaners in the list.
    "hbase.master.logcleaner.plugins": string |*"org.apache.hadoop.hbase.master.cleaner.TimeToLiveLogCleaner,org.apache.hadoop.hbase.master.cleaner.TimeToLiveProcedureWALCleaner,org.apache.hadoop.hbase.master.cleaner.TimeToLiveMasterLocalStoreWALCleaner"

    // How long a WAL remain in the archive ({hbase.rootdir}/oldWALs) directory, after which it will be cleaned by a Master thread. The value is in milliseconds.
    "hbase.master.logcleaner.ttl": int |*600000

    // A comma-separated list of BaseHFileCleanerDelegate invoked by the HFileCleaner service. These HFiles cleaners are called in order, so put the cleaner that prunes the most files in front. To implement your own BaseHFileCleanerDelegate, just put it in HBase’s classpath and add the fully qualified class name here. Always add the above default hfile cleaners in the list as they will be overwritten in hbase-site.xml.
    "hbase.master.hfilecleaner.plugins": string |*"org.apache.hadoop.hbase.master.cleaner.TimeToLiveHFileCleaner,org.apache.hadoop.hbase.master.cleaner.TimeToLiveMasterLocalStoreHFileCleaner"

    // Whether or not the Master listens to the Master web UI port (hbase.master.info.port) and redirects requests to the web UI server shared by the Master and RegionServer. Config. makes sense when Master is serving Regions (not the default).
    "hbase.master.infoserver.redirect": bool |*true

    // Splitting a region, how long to wait on the file-splitting step before aborting the attempt. Default: 600000. This setting used to be known as hbase.regionserver.fileSplitTimeout in hbase-1.x. Split is now run master-side hence the rename (If a 'hbase.master.fileSplitTimeout' setting found, will use it to prime the current 'hbase.master.fileSplitTimeout' Configuration.
    "hbase.master.fileSplitTimeout": int |*600000

    // The port the HBase RegionServer binds to.
    "hbase.regionserver.port": int |*16020

    // The port for the HBase RegionServer web UI Set to -1 if you do not want the RegionServer UI to run.
    "hbase.regionserver.info.port": int & >=1 & <=65535 |*16030

    // The address for the HBase RegionServer web UI
    "hbase.regionserver.info.bindAddress": string |*"0.0.0.0"

    // Whether or not the Master or RegionServer UI should search for a port to bind to. Enables automatic port search if hbase.regionserver.info.port is already in use. Useful for testing, turned off by default.
    "hbase.regionserver.info.port.auto": bool |*false

    // Count of RPC Listener instances spun up on RegionServers. Same property is used by the Master for count of master handlers. Too many handlers can be counter-productive. Make it a multiple of CPU count. If mostly read-only, handlers count close to cpu count does well. Start with twice the CPU count and tune from there.
    "hbase.regionserver.handler.count": int |*30

    // Factor to determine the number of call queues. A value of 0 means a single queue shared between all the handlers. A value of 1 means that each handler has its own queue.
    "hbase.ipc.server.callqueue.handler.factor": float |*0.1

    // Split the call queues into read and write queues. The specified interval (which should be between 0.0 and 1.0) will be multiplied by the number of call queues. A value of 0 indicate to not split the call queues, meaning that both read and write requests will be pushed to the same set of queues. A value lower than 0.5 means that there will be less read queues than write queues. A value of 0.5 means there will be the same number of read and write queues. A value greater than 0.5 means that there will be more read queues than write queues. A value of 1.0 means that all the queues except one are used to dispatch read requests. Example: Given the total number of call queues being 10 a read.ratio of 0 means that: the 10 queues will contain both read/write requests. a read.ratio of 0.3 means that: 3 queues will contain only read requests and 7 queues will contain only write requests. a read.ratio of 0.5 means that: 5 queues will contain only read requests and 5 queues will contain only write requests. a read.ratio of 0.8 means that: 8 queues will contain only read requests and 2 queues will contain only write requests. a read.ratio of 1 means that: 9 queues will contain only read requests and 1 queues will contain only write requests.
    "hbase.ipc.server.callqueue.read.ratio": int |*0

    // Given the number of read call queues, calculated from the total number of call queues multiplied by the callqueue.read.ratio, the scan.ratio property will split the read call queues into small-read and long-read queues. A value lower than 0.5 means that there will be less long-read queues than short-read queues. A value of 0.5 means that there will be the same number of short-read and long-read queues. A value greater than 0.5 means that there will be more long-read queues than short-read queues A value of 0 or 1 indicate to use the same set of queues for gets and scans. Example: Given the total number of read call queues being 8 a scan.ratio of 0 or 1 means that: 8 queues will contain both long and short read requests. a scan.ratio of 0.3 means that: 2 queues will contain only long-read requests and 6 queues will contain only short-read requests. a scan.ratio of 0.5 means that: 4 queues will contain only long-read requests and 4 queues will contain only short-read requests. a scan.ratio of 0.8 means that: 6 queues will contain only long-read requests and 2 queues will contain only short-read requests.
    "hbase.ipc.server.callqueue.scan.ratio": int |*0

    // Interval between messages from the RegionServer to Master in milliseconds.
    "hbase.regionserver.msginterval": int |*3000

    // Period at which we will roll the commit log regardless of how many edits it has.
    "hbase.regionserver.logroll.period": int |*3600000

    // The number of consecutive WAL close errors we will allow before triggering a server abort. A setting of 0 will cause the region server to abort if closing the current WAL writer fails during log rolling. Even a small value (2 or 3) will allow a region server to ride over transient HDFS errors.
    "hbase.regionserver.logroll.errors.tolerated": int |*2

    // Maximum size of all memstores in a region server before new updates are blocked and flushes are forced. Defaults to 40% of heap (0.4). Updates are blocked and flushes are forced until size of all memstores in a region server hits hbase.regionserver.global.memstore.size.lower.limit. The default value in this configuration has been intentionally left empty in order to honor the old hbase.regionserver.global.memstore.upperLimit property if present.
    "hbase.regionserver.global.memstore.size": string |*"none"

    // Maximum size of all memstores in a region server before flushes are forced. Defaults to 95% of hbase.regionserver.global.memstore.size (0.95). A 100% value for this value causes the minimum possible flushing to occur when updates are blocked due to memstore limiting. The default value in this configuration has been intentionally left empty in order to honor the old hbase.regionserver.global.memstore.lowerLimit property if present.
    "hbase.regionserver.global.memstore.size.lower.limit": string |*"none"

    // Determines the type of memstore to be used for system tables like META, namespace tables etc. By default NONE is the type and hence we use the default memstore for all the system tables. If we need to use compacting memstore for system tables then set this property to BASIC/EAGER
    "hbase.systemtables.compacting.memstore.type": string & "NONE" | "BASIC" | "EAGER" |*"NONE"

    // Maximum amount of time an edit lives in memory before being automatically flushed. Default 1 hour. Set it to 0 to disable automatic flushing.
    "hbase.regionserver.optionalcacheflushinterval": int |*3600000

    // The name of the Network Interface from which a region server should report its IP address.
    "hbase.regionserver.dns.interface": string |*"default"

    // The host name or IP address of the name server (DNS) which a region server should use to determine the host name used by the master for communication and display purposes.
    "hbase.regionserver.dns.nameserver": string |*"default"

    // A split policy determines when a region should be split. The various other split policies that are available currently are BusyRegionSplitPolicy, ConstantSizeRegionSplitPolicy, DisabledRegionSplitPolicy, DelimitedKeyPrefixRegionSplitPolicy, KeyPrefixRegionSplitPolicy, and SteppingSplitPolicy. DisabledRegionSplitPolicy blocks manual region splitting.
    "hbase.regionserver.region.split.policy": string |*"org.apache.hadoop.hbase.regionserver.SteppingSplitPolicy"

    // Limit for the number of regions after which no more region splitting should take place. This is not hard limit for the number of regions but acts as a guideline for the regionserver to stop splitting after a certain limit. Default is set to 1000.
    "hbase.regionserver.regionSplitLimit": int |*1000

    // ZooKeeper session timeout in milliseconds. It is used in two different ways. First, this value is used in the ZK client that HBase uses to connect to the ensemble. It is also used by HBase when it starts a ZK server and it is passed as the 'maxSessionTimeout'. See https://zookeeper.apache.org/doc/current/zookeeperProgrammers.html#ch_zkSessions. For example, if an HBase region server connects to a ZK ensemble that’s also managed by HBase, then the session timeout will be the one specified by this configuration. But, a region server that connects to an ensemble managed with a different configuration will be subjected that ensemble’s maxSessionTimeout. So, even though HBase might propose using 90 seconds, the ensemble can have a max timeout lower than this and it will take precedence. The current default maxSessionTimeout that ZK ships with is 40 seconds, which is lower than HBase’s.
    "zookeeper.session.timeout": int |*90000

    // Root ZNode for HBase in ZooKeeper. All of HBase’s ZooKeeper files that are configured with a relative path will go under this node. By default, all of HBase’s ZooKeeper file paths are configured with a relative path, so they will all go under this directory unless changed.
    "zookeeper.znode.parent": string |*"/hbase"

    // Root ZNode for access control lists.
    "zookeeper.znode.acl.parent": string |*"acl"

    // The name of the Network Interface from which a ZooKeeper server should report its IP address.
    "hbase.zookeeper.dns.interface": string |*"default"

    // The host name or IP address of the name server (DNS) which a ZooKeeper server should use to determine the host name used by the master for communication and display purposes.
    "hbase.zookeeper.dns.nameserver": string |*"default"

    // Port used by ZooKeeper peers to talk to each other. See https://zookeeper.apache.org/doc/r3.4.10/zookeeperStarted.html#sc_RunningReplicatedZooKeeper for more information.
    "hbase.zookeeper.peerport": int & >=1 & <=65535 |*2888

    // Port used by ZooKeeper for leader election. See https://zookeeper.apache.org/doc/r3.4.10/zookeeperStarted.html#sc_RunningReplicatedZooKeeper for more information.
    "hbase.zookeeper.leaderport": int  & >=1 & <=65535 |*3888

    // Property from ZooKeeper’s config zoo.cfg. The number of ticks that the initial synchronization phase can take.
    "hbase.zookeeper.property.initLimit": int |*10

    // Property from ZooKeeper’s config zoo.cfg. The number of ticks that can pass between sending a request and getting an acknowledgment.
    "hbase.zookeeper.property.syncLimit": int |*5

    // Property from ZooKeeper’s config zoo.cfg. The directory where the snapshot is stored.
    "hbase.zookeeper.property.dataDir": string |*"${hbase.tmp.dir}/zookeeper"

    // Property from ZooKeeper’s config zoo.cfg. The port at which the clients will connect.
    "hbase.zookeeper.property.clientPort": in  & >=1 & <=65535 |*2181

    // Property from ZooKeeper’s config zoo.cfg. Limit on number of concurrent connections (at the socket level) that a single client, identified by IP address, may make to a single member of the ZooKeeper ensemble. Set high to avoid zk connection issues running standalone and pseudo-distributed.
    "hbase.zookeeper.property.maxClientCnxns": int |*300

    // Default size of the BufferedMutator write buffer in bytes. A bigger buffer takes more memory — on both the client and server side since server instantiates the passed write buffer to process it — but a larger buffer size reduces the number of RPCs made. For an estimate of server-side memory-used, evaluate hbase.client.write.buffer * hbase.regionserver.handler.count
    "hbase.client.write.buffer": int |*2097152

    // General client pause value. Used mostly as value to wait before running a retry of a failed get, region lookup, etc. See hbase.client.retries.number for description of how we backoff from this initial pause amount and how this pause works w/ retries.
    "hbase.client.pause": int |*100

    // Pause time when encountering an exception indicating a server is overloaded, CallQueueTooBigException or CallDroppedException. Set this property to a higher value than hbase.client.pause if you observe frequent CallQueueTooBigException or CallDroppedException from the same RegionServer and the call queue there keeps filling up. This config used to be called hbase.client.pause.cqtbe, which has been deprecated as of 2.5.0.
    "hbase.client.pause.server.overloaded": string |*"none"

    // Maximum retries. Used as maximum for all retryable operations such as the getting of a cell’s value, starting a row update, etc. Retry interval is a rough function based on hbase.client.pause. At first we retry at this interval but then with backoff, we pretty quickly reach retrying every ten seconds. See HConstants#RETRY_BACKOFF for how the backup ramps up. Change this setting and hbase.client.pause to suit your workload.
    "hbase.client.retries.number": int |*15

    // The maximum number of concurrent mutation tasks a single HTable instance will send to the cluster.
    "hbase.client.max.total.tasks": int |*100

    // The maximum number of concurrent mutation tasks a single HTable instance will send to a single region server.
    "hbase.client.max.perserver.tasks": int |*2

    // The maximum number of concurrent mutation tasks the client will maintain to a single Region. That is, if there is already hbase.client.max.perregion.tasks writes in progress for this region, new puts won’t be sent to this region until some writes finishes.
    "hbase.client.max.perregion.tasks": int |*1

    // The max number of concurrent pending requests for one server in all client threads (process level). Exceeding requests will be thrown ServerTooBusyException immediately to prevent user’s threads being occupied and blocked by only one slow region server. If you use a fix number of threads to access HBase in a synchronous way, set this to a suitable value which is related to the number of threads will help you. See https://issues.apache.org/jira/browse/HBASE-16388 for details.
    "hbase.client.perserver.requests.threshold": int |*2147483647

    // Number of rows that we try to fetch when calling next on a scanner if it is not served from (local, client) memory. This configuration works together with hbase.client.scanner.max.result.size to try and use the network efficiently. The default value is Integer.MAX_VALUE by default so that the network will fill the chunk size defined by hbase.client.scanner.max.result.size rather than be limited by a particular number of rows since the size of rows varies table to table. If you know ahead of time that you will not require more than a certain number of rows from a scan, this configuration should be set to that row limit via Scan#setCaching. Higher caching values will enable faster scanners but will eat up more memory and some calls of next may take longer and longer times when the cache is empty. Do not set this value such that the time between invocations is greater than the scanner timeout; i.e. hbase.client.scanner.timeout.period
    "hbase.client.scanner.caching": int |*2147483647

    // Specifies the combined maximum allowed size of a KeyValue instance. This is to set an upper boundary for a single entry saved in a storage file. Since they cannot be split it helps avoiding that a region cannot be split any further because the data is too large. It seems wise to set this to a fraction of the maximum region size. Setting it to zero or less disables the check.
    "hbase.client.keyvalue.maxsize": int |*10485760

    // Maximum allowed size of an individual cell, inclusive of value and all key components. A value of 0 or less disables the check. The default value is 10MB. This is a safety setting to protect the server from OOM situations.
    "hbase.server.keyvalue.maxsize": int |*10485760

    // Client scanner lease period in milliseconds.
    "hbase.client.scanner.timeout.period": int |*60000

    // Unknown
    "hbase.client.localityCheck.threadPoolSize": int |*2

    // Maximum retries. This is maximum number of iterations to atomic bulk loads are attempted in the face of splitting operations 0 means never give up.
    "hbase.bulkload.retries.number": int |*10

    // Request Compaction after bulkload immediately. If bulkload is continuous, the triggered compactions may increase load, bring about performance side effect.
    "hbase.compaction.after.bulkload.enable": bool |*false

    // The max percent of regions in transition when balancing. The default value is 1.0. So there are no balancer throttling. If set this config to 0.01, It means that there are at most 1% regions in transition when balancing. Then the cluster’s availability is at least 99% when balancing.
    "hbase.master.balancer.maxRitPercent": float |*1.0

    // Period at which the region balancer runs in the Master, in milliseconds.
    "hbase.balancer.period": int |*300000

    // The load balancer can trigger for several reasons. This value controls one of those reasons. Run the balancer if any regionserver has a region count outside the range of average +/- (average * slop) regions. If the value of slop is negative, disable sloppiness checks. The balancer can still run for other reasons, but sloppiness will not be one of them. If the value of slop is 0, run the balancer if any server has a region count more than 1 from the average. If the value of slop is 100, run the balancer if any server has a region count greater than 101 times the average. The default value of this parameter is 0.2, which runs the balancer if any server has a region count less than 80% of the average, or greater than 120% of the average. Note that for the default StochasticLoadBalancer, this does not guarantee any balancing actions will be taken, but only that the balancer will attempt to run.
    "hbase.regions.slop": float |*0.2

    // Period at which the region normalizer runs in the Master, in milliseconds.
    "hbase.normalizer.period": int |*300000

    // Whether to split a region as part of normalization.
    "hbase.normalizer.split.enabled": bool |*true

    // Whether to merge a region as part of normalization.
    "hbase.normalizer.merge.enabled": bool |*true

    // The minimum number of regions in a table to consider it for merge normalization.
    "hbase.normalizer.merge.min.region.count": int |*3

    // The minimum age for a region to be considered for a merge, in days.
    "hbase.normalizer.merge.min_region_age.days": int |*3

    // The minimum size for a region to be considered for a merge, in whole MBs.
    "hbase.normalizer.merge.min_region_size.mb": int |*1

    // The maximum number of region count in a merge request for merge normalization.
    "hbase.normalizer.merge.merge_request_max_number_of_regions": int |*100

    // This config is used to set default behaviour of normalizer at table level. To override this at table level one can set NORMALIZATION_ENABLED at table descriptor level and that property will be honored
    "hbase.table.normalization.enabled": bool |*false

    // In master side, this config is the period used for FS related behaviors: checking if hdfs is out of safe mode, setting or checking hbase.version file, setting or checking hbase.id file. Using default value should be fine. In regionserver side, this config is used in several places: flushing check interval, compaction check interval, wal rolling check interval. Specially, admin can tune flushing and compaction check interval by hbase.regionserver.flush.check.period and hbase.regionserver.compaction.check.period. (in milliseconds)
    "hbase.server.thread.wakefrequency": int |*10000

    // It determines the flushing check period of PeriodicFlusher in regionserver. If unset, it uses hbase.server.thread.wakefrequency as default value. (in milliseconds)
    "hbase.regionserver.flush.check.period": string |*"${hbase.server.thread.wakefrequency}"

    // It determines the compaction check period of CompactionChecker in regionserver. If unset, it uses hbase.server.thread.wakefrequency as default value. (in milliseconds)
    "hbase.regionserver.compaction.check.period": string |*"${hbase.server.thread.wakefrequency}"

    // How many times to retry attempting to write a version file before just aborting. Each attempt is separated by the hbase.server.thread.wakefrequency milliseconds.
    "hbase.server.versionfile.writeattempts": int |*3

    // Memstore will be flushed to disk if size of the memstore exceeds this number of bytes. Value is checked by a thread that runs every hbase.server.thread.wakefrequency.
    "hbase.hregion.memstore.flush.size": int |*134217728

    // If FlushLargeStoresPolicy is used and there are multiple column families, then every time that we hit the total memstore limit, we find out all the column families whose memstores exceed a "lower bound" and only flush them while retaining the others in memory. The "lower bound" will be "hbase.hregion.memstore.flush.size / column_family_number" by default unless value of this property is larger than that. If none of the families have their memstore size more than lower bound, all the memstores will be flushed (just as usual).
    "hbase.hregion.percolumnfamilyflush.size.lower.bound.min": int |*16777216

    // If the memstores in a region are this size or larger when we go to close, run a "pre-flush" to clear out memstores before we put up the region closed flag and take the region offline. On close, a flush is run under the close flag to empty memory. During this time the region is offline and we are not taking on any writes. If the memstore content is large, this flush could take a long time to complete. The preflush is meant to clean out the bulk of the memstore before putting up the close flag and taking the region offline so the flush that runs under the close flag has little to do.
    "hbase.hregion.preclose.flush.size": int |*5242880

    // Block updates if memstore has hbase.hregion.memstore.block.multiplier times hbase.hregion.memstore.flush.size bytes. Useful preventing runaway memstore during spikes in update traffic. Without an upper-bound, memstore fills such that when it flushes the resultant flush files take a long time to compact or split, or worse, we OOME.
    "hbase.hregion.memstore.block.multiplier": int |*4

    // Enables the MemStore-Local Allocation Buffer, a feature which works to prevent heap fragmentation under heavy write loads. This can reduce the frequency of stop-the-world GC pauses on large heaps.
    "hbase.hregion.memstore.mslab.enabled": bool |*true

    // The maximum byte size of a chunk in the MemStoreLAB. Unit: bytes
    "hbase.hregion.memstore.mslab.chunksize": int |*2097152

    // The amount of off-heap memory all MemStores in a RegionServer may use. A value of 0 means that no off-heap memory will be used and all chunks in MSLAB will be HeapByteBuffer, otherwise the non-zero value means how many megabyte of off-heap memory will be used for chunks in MSLAB and all chunks in MSLAB will be DirectByteBuffer. Unit: megabytes.
    "hbase.regionserver.offheap.global.memstore.size": int |*0

    // The maximal size of one allocation in the MemStoreLAB, if the desired byte size exceed this threshold then it will be just allocated from JVM heap rather than MemStoreLAB.
    "hbase.hregion.memstore.mslab.max.allocation": int |*262144

    // Maximum file size. If the sum of the sizes of a region’s HFiles has grown to exceed this value, the region is split in two. There are two choices of how this option works, the first is when any store’s size exceed the threshold then split, and the other is overall region’s size exceed the threshold then split, it can be configed by hbase.hregion.split.overallfiles.
    "hbase.hregion.max.filesize": int |*10737418240

    // If we should sum overall region files size when check to split.
    "hbase.hregion.split.overallfiles": bool |*true

    // Time between major compactions, expressed in milliseconds. Set to 0 to disable time-based automatic major compactions. User-requested and size-based major compactions will still run. This value is multiplied by hbase.hregion.majorcompaction.jitter to cause compaction to start at a somewhat-random time during a given window of time. The default value is 7 days, expressed in milliseconds. If major compactions are causing disruption in your environment, you can configure them to run at off-peak times for your deployment, or disable time-based major compactions by setting this parameter to 0, and run major compactions in a cron job or by another external mechanism.
    "hbase.hregion.majorcompaction": int |*604800000

    // A multiplier applied to hbase.hregion.majorcompaction to cause compaction to occur a given amount of time either side of hbase.hregion.majorcompaction. The smaller the number, the closer the compactions will happen to the hbase.hregion.majorcompaction interval.
    "hbase.hregion.majorcompaction.jitter": float |*0.50

    // If more than or equal to this number of StoreFiles exist in any one Store (one StoreFile is written per flush of MemStore), a compaction is run to rewrite all StoreFiles into a single StoreFile. Larger values delay compaction, but when compaction does occur, it takes longer to complete.
    "hbase.hstore.compactionThreshold": int |*3

    // Enable/disable compactions on by setting true/false. We can further switch compactions dynamically with the compaction_switch shell command.
    "hbase.regionserver.compaction.enabled": bool |*true

    // The number of flush threads. With fewer threads, the MemStore flushes will be queued. With more threads, the flushes will be executed in parallel, increasing the load on HDFS, and potentially causing more compactions.
    "hbase.hstore.flusher.count": int |*2

    // If more than this number of StoreFiles exist in any one Store (one StoreFile is written per flush of MemStore), updates are blocked for this region until a compaction is completed, or until hbase.hstore.blockingWaitTime has been exceeded.
    "hbase.hstore.blockingStoreFiles": int |*16

    // The time for which a region will block updates after reaching the StoreFile limit defined by hbase.hstore.blockingStoreFiles. After this time has elapsed, the region will stop blocking updates even if a compaction has not been completed.
    "hbase.hstore.blockingWaitTime": int |*90000

    // The minimum number of StoreFiles which must be eligible for compaction before compaction can run. The goal of tuning hbase.hstore.compaction.min is to avoid ending up with too many tiny StoreFiles to compact. Setting this value to 2 would cause a minor compaction each time you have two StoreFiles in a Store, and this is probably not appropriate. If you set this value too high, all the other values will need to be adjusted accordingly. For most cases, the default value is appropriate (empty value here, results in 3 by code logic). In previous versions of HBase, the parameter hbase.hstore.compaction.min was named hbase.hstore.compactionThreshold.
    "hbase.hstore.compaction.min": string |*"none"

    // The maximum number of StoreFiles which will be selected for a single minor compaction, regardless of the number of eligible StoreFiles. Effectively, the value of hbase.hstore.compaction.max controls the length of time it takes a single compaction to complete. Setting it larger means that more StoreFiles are included in a compaction. For most cases, the default value is appropriate.
    "hbase.hstore.compaction.max": int |*10

    // A StoreFile (or a selection of StoreFiles, when using ExploringCompactionPolicy) smaller than this size will always be eligible for minor compaction. HFiles this size or larger are evaluated by hbase.hstore.compaction.ratio to determine if they are eligible. Because this limit represents the "automatic include" limit for all StoreFiles smaller than this value, this value may need to be reduced in write-heavy environments where many StoreFiles in the 1-2 MB range are being flushed, because every StoreFile will be targeted for compaction and the resulting StoreFiles may still be under the minimum size and require further compaction. If this parameter is lowered, the ratio check is triggered more quickly. This addressed some issues seen in earlier versions of HBase but changing this parameter is no longer necessary in most situations. Default: 128 MB expressed in bytes.
    "hbase.hstore.compaction.min.size": int |*134217728

    // A StoreFile (or a selection of StoreFiles, when using ExploringCompactionPolicy) larger than this size will be excluded from compaction. The effect of raising hbase.hstore.compaction.max.size is fewer, larger StoreFiles that do not get compacted often. If you feel that compaction is happening too often without much benefit, you can try raising this value. Default: the value of LONG.MAX_VALUE, expressed in bytes.
    "hbase.hstore.compaction.max.size": int |*9223372036854775807

    // For minor compaction, this ratio is used to determine whether a given StoreFile which is larger than hbase.hstore.compaction.min.size is eligible for compaction. Its effect is to limit compaction of large StoreFiles. The value of hbase.hstore.compaction.ratio is expressed as a floating-point decimal. A large ratio, such as 10, will produce a single giant StoreFile. Conversely, a low value, such as .25, will produce behavior similar to the BigTable compaction algorithm, producing four StoreFiles. A moderate value of between 1.0 and 1.4 is recommended. When tuning this value, you are balancing write costs with read costs. Raising the value (to something like 1.4) will have more write costs, because you will compact larger StoreFiles. However, during reads, HBase will need to seek through fewer StoreFiles to accomplish the read. Consider this approach if you cannot take advantage of Bloom filters. Otherwise, you can lower this value to something like 1.0 to reduce the background cost of writes, and use Bloom filters to control the number of StoreFiles touched during reads. For most cases, the default value is appropriate.
    "hbase.hstore.compaction.ratio": string |*"1.2F"

    // Allows you to set a different (by default, more aggressive) ratio for determining whether larger StoreFiles are included in compactions during off-peak hours. Works in the same way as hbase.hstore.compaction.ratio. Only applies if hbase.offpeak.start.hour and hbase.offpeak.end.hour are also enabled.
    "hbase.hstore.compaction.ratio.offpeak": string |*"5.0F"

    // The amount of time to delay purging of delete markers with future timestamps. If unset, or set to 0, all delete markers, including those with future timestamps, are purged during the next major compaction. Otherwise, a delete marker is kept until the major compaction which occurs after the marker’s timestamp plus the value of this setting, in milliseconds.
    "hbase.hstore.time.to.purge.deletes": int |*0

    // The start of off-peak hours, expressed as an integer between 0 and 23, inclusive. Set to -1 to disable off-peak.
    "hbase.offpeak.start.hour": int |*-1

    // The end of off-peak hours, expressed as an integer between 0 and 23, inclusive. Set to -1 to disable off-peak.
    "hbase.offpeak.end.hour": int |*-1

    // There are two different thread pools for compactions, one for large compactions and the other for small compactions. This helps to keep compaction of lean tables (such as hbase:meta) fast. If a compaction is larger than this threshold, it goes into the large compaction pool. In most cases, the default value is appropriate. Default: 2 x hbase.hstore.compaction.max x hbase.hregion.memstore.flush.size (which defaults to 128MB). The value field assumes that the value of hbase.hregion.memstore.flush.size is unchanged from the default.
    "hbase.regionserver.thread.compaction.throttle": int |*2684354560

    // Specifies whether to drop pages read/written into the system page cache by major compactions. Setting it to true helps prevent major compactions from polluting the page cache, which is almost always required, especially for clusters with low/moderate memory to storage ratio.
    "hbase.regionserver.majorcompaction.pagecache.drop": bool |*true

    // Specifies whether to drop pages read/written into the system page cache by minor compactions. Setting it to true helps prevent minor compactions from polluting the page cache, which is most beneficial on clusters with low memory to storage ratio or very write heavy clusters. You may want to set it to false under moderate to low write workload when bulk of the reads are on the most recently written data.
    "hbase.regionserver.minorcompaction.pagecache.drop": bool |*true

    // The maximum number of KeyValues to read and then write in a batch when flushing or compacting. Set this lower if you have big KeyValues and problems with Out Of Memory Exceptions Set this higher if you have wide, small rows.
    "hbase.hstore.compaction.kv.max": int |*10

    // Enables StoreFileScanner parallel-seeking in StoreScanner, a feature which can reduce response latency under special conditions.
    "hbase.storescanner.parallel.seek.enable": bool |*false

    // The default thread pool size if parallel-seeking feature enabled.
    "hbase.storescanner.parallel.seek.threads": int | *10

    // The eviction policy for the L1 block cache (LRU or TinyLFU).
    "hfile.block.cache.policy": string & "LRU" | "TinyLFU" |*"LRU"

    // Percentage of maximum heap (-Xmx setting) to allocate to block cache used by a StoreFile. Default of 0.4 means allocate 40%. Set to 0 to disable but it’s not recommended; you need at least enough cache to hold the storefile indices.
    "hfile.block.cache.size": float | *0.4

    // This allows to put non-root multi-level index blocks into the block cache at the time the index is being written.
    "hfile.block.index.cacheonwrite": bool | *false

    // When the size of a leaf-level, intermediate-level, or root-level index block in a multi-level block index grows to this size, the block is written out and a new block is started.
    "hfile.index.block.max.size": int | *131072

    // Where to store the contents of the bucketcache. One of: offheap, file, files, mmap or pmem. If a file or files, set it to file(s):PATH_TO_FILE. mmap means the content will be in an mmaped file. Use mmap:PATH_TO_FILE. 'pmem' is bucket cache over a file on the persistent memory device. Use pmem:PATH_TO_FILE. See http://hbase.apache.org/book.html#offheap.blockcache for more information.
    "hbase.bucketcache.ioengine": string |*"none"

    // The target lower bound on aggregate compaction throughput, in bytes/sec. Allows you to tune the minimum available compaction throughput when the PressureAwareCompactionThroughputController throughput controller is active. (It is active by default.)
    "hbase.hstore.compaction.throughput.lower.bound": int |*52428800

    // The target upper bound on aggregate compaction throughput, in bytes/sec. Allows you to control aggregate compaction throughput demand when the PressureAwareCompactionThroughputController throughput controller is active. (It is active by default.) The maximum throughput will be tuned between the lower and upper bounds when compaction pressure is within the range [0.0, 1.0]. If compaction pressure is 1.0 or greater the higher bound will be ignored until pressure returns to the normal range.
    "hbase.hstore.compaction.throughput.higher.bound": int |*104857600

    // It is the total capacity in megabytes of BucketCache. Default: 0.0
    "hbase.bucketcache.size": string |*"none"

    // A comma-separated list of sizes for buckets for the bucketcache. Can be multiple sizes. List block sizes in order from smallest to largest. The sizes you use will depend on your data access patterns. Must be a multiple of 256 else you will run into 'java.io.IOException: Invalid HFile block magic' when you go to read from cache. If you specify no values here, then you pick up the default bucketsizes set in code (See BucketAllocator#DEFAULT_BUCKET_SIZES).
    "hbase.bucketcache.bucket.sizes": string |*"none"

    // The HFile format version to use for new files. Version 3 adds support for tags in hfiles (See http://hbase.apache.org/book.html#hbase.tags). Also see the configuration 'hbase.replication.rpc.codec'.
    "hfile.format.version": int |*3

    // Enables cache-on-write for inline blocks of a compound Bloom filter.
    "hfile.block.bloom.cacheonwrite": bool |*false

    // The size in bytes of a single block ("chunk") of a compound Bloom filter. This size is approximate, because Bloom blocks can only be inserted at data block boundaries, and the number of keys per data block varies.
    "io.storefile.bloom.block.size": int |*131072

    // Whether an HFile block should be added to the block cache when the block is finished.
    "hbase.rs.cacheblocksonwrite": bool |*false

    // This is for the RPC layer to define how long (millisecond) HBase client applications take for a remote call to time out. It uses pings to check connections but will eventually throw a TimeoutException.
    "hbase.rpc.timeout": int |*60000

    // Operation timeout is a top-level restriction (millisecond) that makes sure a blocking operation in Table will not be blocked more than this. In each operation, if rpc request fails because of timeout or other reason, it will retry until success or throw RetriesExhaustedException. But if the total time being blocking reach the operation timeout before retries exhausted, it will break early and throw SocketTimeoutException.
    "hbase.client.operation.timeout": int |*1200000

    // The number of cells scanned in between heartbeat checks. Heartbeat checks occur during the processing of scans to determine whether or not the server should stop scanning in order to send back a heartbeat message to the client. Heartbeat messages are used to keep the client-server connection alive during long running scans. Small values mean that the heartbeat checks will occur more often and thus will provide a tighter bound on the execution time of the scan. Larger values mean that the heartbeat checks occur less frequently
    "hbase.cells.scanned.per.heartbeat.check": int |*10000

    // This is another version of "hbase.rpc.timeout". For those RPC operation within cluster, we rely on this configuration to set a short timeout limitation for short operation. For example, short rpc timeout for region server’s trying to report to active master can benefit quicker master failover process.
    "hbase.rpc.shortoperation.timeout": int |*10000

    // Set no delay on rpc socket connections. See http://docs.oracle.com/javase/1.5.0/docs/api/java/net/Socket.html#getTcpNoDelay()
    "hbase.ipc.client.tcpnodelay": bool |*true

    // This config is for experts: don’t set its value unless you really know what you are doing. When set to a non-empty value, this represents the (external facing) hostname for the underlying server. See https://issues.apache.org/jira/browse/HBASE-12954 for details.
    "hbase.unsafe.regionserver.hostname": string |*"none"

    // This config is for experts: don’t set its value unless you really know what you are doing. When set to true, regionserver will use the current node hostname for the servername and HMaster will skip reverse DNS lookup and use the hostname sent by regionserver instead. Note that this config and hbase.unsafe.regionserver.hostname are mutually exclusive. See https://issues.apache.org/jira/browse/HBASE-18226 for more details.
    "hbase.unsafe.regionserver.hostname.disable.master.reversedns": bool |*false

    // Full path to the kerberos keytab file to use for logging in the configured HMaster server principal.
    "hbase.master.keytab.file": string |*"none"

    // Ex. "hbase/_HOST@EXAMPLE.COM". The kerberos principal name that should be used to run the HMaster process. The principal name should be in the form: user/hostname@DOMAIN. If "_HOST" is used as the hostname portion, it will be replaced with the actual hostname of the running instance.
    "hbase.master.kerberos.principal": string |*"none"

    // Full path to the kerberos keytab file to use for logging in the configured HRegionServer server principal.
    "hbase.regionserver.keytab.file": string |*"none"

    // Ex. "hbase/_HOST@EXAMPLE.COM". The kerberos principal name that should be used to run the HRegionServer process. The principal name should be in the form: user/hostname@DOMAIN. If "_HOST" is used as the hostname portion, it will be replaced with the actual hostname of the running instance. An entry for this principal must exist in the file specified in hbase.regionserver.keytab.file
    "hbase.regionserver.kerberos.principal": string |*"none"

    // The policy configuration file used by RPC servers to make authorization decisions on client requests. Only used when HBase security is enabled.
    "hadoop.policy.file": string |*"hbase-policy.xml"

    // List of users or groups (comma-separated), who are allowed full privileges, regardless of stored ACLs, across the cluster. Only used when HBase security is enabled.
    "hbase.superuser": string |*"none"

    // The update interval for master key for authentication tokens in servers in milliseconds. Only used when HBase security is enabled.
    "hbase.auth.key.update.interval": int |*86400000

    // The maximum lifetime in milliseconds after which an authentication token expires. Only used when HBase security is enabled.
    "hbase.auth.token.max.lifetime": int |*604800000

    // When a client is configured to attempt a secure connection, but attempts to connect to an insecure server, that server may instruct the client to switch to SASL SIMPLE (unsecure) authentication. This setting controls whether or not the client will accept this instruction from the server. When false (the default), the client will not allow the fallback to SIMPLE authentication, and will abort the connection.
    "hbase.ipc.client.fallback-to-simple-auth-allowed": bool |*false

    // When a server is configured to require secure connections, it will reject connection attempts from clients using SASL SIMPLE (unsecure) authentication. This setting allows secure servers to accept SASL SIMPLE connections from clients when the client requests. When false (the default), the server will not allow the fallback to SIMPLE authentication, and will reject the connection. WARNING: This setting should ONLY be used as a temporary measure while converting clients over to secure authentication. It MUST BE DISABLED for secure operation.
    "hbase.ipc.server.fallback-to-simple-auth-allowed": bool |*false

    // This config is for experts: don’t set its value unless you really know what you are doing. When set to true, HBase client using SASL Kerberos will skip reverse DNS lookup and use provided hostname of the destination for the principal instead. See https://issues.apache.org/jira/browse/HBASE-25665 for more details.
    "hbase.unsafe.client.kerberos.hostname.disable.reversedns": bool |*false

    // When this is set to true the webUI and such will display all start/end keys as part of the table details, region names, etc. When this is set to false, the keys are hidden.
    "hbase.display.keys": bool |*true

    // Enables or disables coprocessor loading. If 'false' (disabled), any other coprocessor related configuration will be ignored.
    "hbase.coprocessor.enabled": bool |*true

    // Enables or disables user (aka. table) coprocessor loading. If 'false' (disabled), any table coprocessor attributes in table descriptors will be ignored. If "hbase.coprocessor.enabled" is 'false' this setting has no effect.
    "hbase.coprocessor.user.enabled": bool |*true

    // A comma-separated list of region observer or endpoint coprocessors that are loaded by default on all tables. For any override coprocessor method, these classes will be called in order. After implementing your own Coprocessor, add it to HBase’s classpath and add the fully qualified class name here. A coprocessor can also be loaded on demand by setting HTableDescriptor or the HBase shell.
    "hbase.coprocessor.region.classes": string |*"none"

    // A comma-separated list of org.apache.hadoop.hbase.coprocessor.MasterObserver coprocessors that are loaded by default on the active HMaster process. For any implemented coprocessor methods, the listed classes will be called in order. After implementing your own MasterObserver, just put it in HBase’s classpath and add the fully qualified class name here.
    "hbase.coprocessor.master.classes": string |*"none"

    // Set to true to cause the hosting server (master or regionserver) to abort if a coprocessor fails to load, fails to initialize, or throws an unexpected Throwable object. Setting this to false will allow the server to continue execution but the system wide state of the coprocessor in question will become inconsistent as it will be properly executing in only a subset of servers, so this is most useful for debugging only.
    "hbase.coprocessor.abortonerror": bool |*true

    // The port for the HBase REST server.
    "hbase.rest.port": int & >=1 & <=65535 |*8080

    // Defines the mode the REST server will be started in. Possible values are: false: All HTTP methods are permitted - GET/PUT/POST/DELETE. true: Only the GET method is permitted.
    "hbase.rest.readonly": bool |*false

    // The maximum number of threads of the REST server thread pool. Threads in the pool are reused to process REST requests. This controls the maximum number of requests processed concurrently. It may help to control the memory used by the REST server to avoid OOM issues. If the thread pool is full, incoming requests will be queued up and wait for some free threads.
    "hbase.rest.threads.max": int |*100

    // The minimum number of threads of the REST server thread pool. The thread pool always has at least these number of threads so the REST server is ready to serve incoming requests.
    "hbase.rest.threads.min": int |*2

    // Enables running the REST server to support proxy-user mode.
    "hbase.rest.support.proxyuser": bool |*false

    // Set to true to skip the 'hbase.defaults.for.version' check. Setting this to true can be useful in contexts other than the other side of a maven generation; i.e. running in an IDE. You’ll want to set this boolean to true to avoid seeing the RuntimeException complaint: "hbase-default.xml file seems to be for and old version of HBase (\${hbase.version}), this version is X.X.X-SNAPSHOT"
    "hbase.defaults.for.version.skip": bool |*false

    // Set to true to enable locking the table in zookeeper for schema change operations. Table locking from master prevents concurrent schema modifications to corrupt table state.
    "hbase.table.lock.enable": bool |*true

    // Maximum size of single row in bytes (default is 1 Gb) for Get’ting or Scan’ning without in-row scan flag set. If row size exceeds this limit RowTooBigException is thrown to client.
    "hbase.table.max.rowsize": int |*1073741824

    // The "core size" of the thread pool. New threads are created on every connection until this many threads are created.
    "hbase.thrift.minWorkerThreads": int |*16

    // The maximum size of the thread pool. When the pending request queue overflows, new threads are created until their number reaches this number. After that, the server starts dropping connections.
    "hbase.thrift.maxWorkerThreads": int |*1000

    // The maximum number of pending Thrift connections waiting in the queue. If there are no idle threads in the pool, the server queues requests. Only when the queue overflows, new threads are added, up to hbase.thrift.maxQueuedRequests threads.
    "hbase.thrift.maxQueuedRequests": int |*1000

    // Use Thrift TFramedTransport on the server side. This is the recommended transport for thrift servers and requires a similar setting on the client side. Changing this to false will select the default transport, vulnerable to DoS when malformed requests are issued due to THRIFT-601.
    "hbase.regionserver.thrift.framed": bool |*false

    // Default frame size when using framed transport, in MB
    "hbase.regionserver.thrift.framed.max_frame_size_in_mb": int |*2

    // Use Thrift TCompactProtocol binary serialization protocol.
    "hbase.regionserver.thrift.compact": bool |*false

    // FS Permissions for the root data subdirectory in a secure (kerberos) setup. When master starts, it creates the rootdir with this permissions or sets the permissions if it does not match.
    "hbase.rootdir.perms": int |*700

    // FS Permissions for the root WAL directory in a secure(kerberos) setup. When master starts, it creates the WAL dir with this permissions or sets the permissions if it does not match.
    "hbase.wal.dir.perms": int |*700

    // Enable, if true, that file permissions should be assigned to the files written by the regionserver
    "hbase.data.umask.enable": bool |*false

    // File permissions that should be used to write data files when hbase.data.umask.enable is true
    "hbase.data.umask": int |*0

    // Set to true to allow snapshots to be taken / restored / cloned.
    "hbase.snapshot.enabled": bool |*true

    // Set to true to take a snapshot before the restore operation. The snapshot taken will be used in case of failure, to restore the previous state. At the end of the restore operation this snapshot will be deleted
    "hbase.snapshot.restore.take.failsafe.snapshot": bool |*true

    // Name of the failsafe snapshot taken by the restore operation. You can use the {snapshot.name}, {table.name} and {restore.timestamp} variables to create a name based on what you are restoring.
    "hbase.snapshot.restore.failsafe.name": string |*"hbase-failsafe-{snapshot.name}-{restore.timestamp}"

    // Location where the snapshotting process will occur. The location of the completed snapshots will not change, but the temporary directory where the snapshot process occurs will be set to this location. This can be a separate filesystem than the root directory, for performance increase purposes. See HBASE-21098 for more information
    "hbase.snapshot.working.dir": string |*"none"

    // The number that determines how often we scan to see if compaction is necessary. Normally, compactions are done after some events (such as memstore flush), but if region didn’t receive a lot of writes for some time, or due to different compaction policies, it may be necessary to check it periodically. The interval between checks is hbase.server.compactchecker.interval.multiplier multiplied by hbase.server.thread.wakefrequency.
    "hbase.server.compactchecker.interval.multiplier": int |*1000

    // How long we wait on dfs lease recovery in total before giving up.
    "hbase.lease.recovery.timeout": int |*900000

    // How long between dfs recover lease invocations. Should be larger than the sum of the time it takes for the namenode to issue a block recovery command as part of datanode; dfs.heartbeat.interval and the time it takes for the primary datanode, performing block recovery to timeout on a dead datanode; usually dfs.client.socket-timeout. See the end of HBASE-8389 for more.
    "hbase.lease.recovery.dfs.timeout": int |*64000

    // New column family descriptors will use this value as the default number of versions to keep.
    "hbase.column.max.version": int |*1

    // If set to true, this configuration parameter enables short-circuit local reads.
    "dfs.client.read.shortcircuit": string |*"none"

    // This is a path to a UNIX domain socket that will be used for communication between the DataNode and local HDFS clients, if dfs.client.read.shortcircuit is set to true. If the string "_PORT" is present in this path, it will be replaced by the TCP port of the DataNode. Be careful about permissions for the directory that hosts the shared domain socket; dfsclient will complain if open to other users than the HBase user.
    "dfs.domain.socket.path": string |*"none"

    // If the DFSClient configuration dfs.client.read.shortcircuit.buffer.size is unset, we will use what is configured here as the short circuit read default direct byte buffer size. DFSClient native default is 1MB; HBase keeps its HDFS files open so number of file blocks * 1MB soon starts to add up and threaten OOME because of a shortage of direct memory. So, we set it down from the default. Make it > the default hbase block size set in the HColumnDescriptor which is usually 64k.
    "hbase.dfs.client.read.shortcircuit.buffer.size": int |*131072

    // If set to true (the default), HBase verifies the checksums for hfile blocks. HBase writes checksums inline with the data when it writes out hfiles. HDFS (as of this writing) writes checksums to a separate file than the data file necessitating extra seeks. Setting this flag saves some on i/o. Checksum verification by HDFS will be internally disabled on hfile streams when this flag is set. If the hbase-checksum verification fails, we will switch back to using HDFS checksums (so do not disable HDFS checksums! And besides this feature applies to hfiles only, not to WALs). If this parameter is set to false, then hbase will not verify any checksums, instead it will depend on checksum verification being done in the HDFS client.
    "hbase.regionserver.checksum.verify": bool |*true

    // Number of bytes in a newly created checksum chunk for HBase-level checksums in hfile blocks.
    "hbase.hstore.bytes.per.checksum": int |*16384

    // Name of an algorithm that is used to compute checksums. Possible values are NULL, CRC32, CRC32C.
    "hbase.hstore.checksum.algorithm": string |*"CRC32C"

    // Maximum number of bytes returned when calling a scanner’s next method. Note that when a single row is larger than this limit the row is still returned completely. The default value is 2MB, which is good for 1ge networks. With faster and/or high latency networks this value should be increased.
    "hbase.client.scanner.max.result.size": int |*2097152

    // Maximum number of bytes returned when calling a scanner’s next method. Note that when a single row is larger than this limit the row is still returned completely. The default value is 100MB. This is a safety setting to protect the server from OOM situations.
    "hbase.server.scanner.max.result.size": int |*104857600

    // This setting activates the publication by the master of the status of the region server. When a region server dies and its recovery starts, the master will push this information to the client application, to let them cut the connection immediately instead of waiting for a timeout.
    "hbase.status.published": bool |*false

    // Implementation of the status publication with a multicast message.
    "hbase.status.publisher.class": string |*"org.apache.hadoop.hbase.master.ClusterStatusPublisher$MulticastPublisher"

    // Implementation of the status listener with a multicast message.
    "hbase.status.listener.class": string |*"org.apache.hadoop.hbase.client.ClusterStatusListener$MulticastListener"

    // Multicast address to use for the status publication by multicast.
    "hbase.status.multicast.address.ip": string |*"226.1.1.3"

    // Multicast port to use for the status publication by multicast.
    "hbase.status.multicast.address.port": int  & >=1 & <=65535 |*16100

    // The directory from which the custom filter JARs can be loaded dynamically by the region server without the need to restart. However, an already loaded filter/co-processor class would not be un-loaded. See HBASE-1936 for more details. Does not apply to coprocessors.
    "hbase.dynamic.jars.dir": string |*"${hbase.rootdir}/lib"

    // Controls whether or not secure authentication is enabled for HBase. Possible values are 'simple' (no authentication), and 'kerberos'.
    "hbase.security.authentication": string & "simple" | "kerberos" |*"simple"

    // Servlet filters for REST service.
    "hbase.rest.filter.classes": string |*"org.apache.hadoop.hbase.rest.filter.GzipFilter"

    // Class used to execute the regions balancing when the period occurs. See the class comment for more on how it works http://hbase.apache.org/devapidocs/org/apache/hadoop/hbase/master/balancer/StochasticLoadBalancer.html It replaces the DefaultLoadBalancer as the default (since renamed as the SimpleLoadBalancer).
    "hbase.master.loadbalancer.class": string |*"org.apache.hadoop.hbase.master.balancer.StochasticLoadBalancer"

    // Factor Table name when the balancer runs. Default: false.
    "hbase.master.loadbalance.bytable": bool |*false

    // Class used to execute the region normalization when the period occurs. See the class comment for more on how it works http://hbase.apache.org/devapidocs/org/apache/hadoop/hbase/master/normalizer/SimpleRegionNormalizer.html
    "hbase.master.normalizer.class": string |*"org.apache.hadoop.hbase.master.normalizer.SimpleRegionNormalizer"

    // Set to true to enable protection against cross-site request forgery (CSRF)
    "hbase.rest.csrf.enabled": bool |*false

    // A comma-separated list of regular expressions used to match against an HTTP request’s User-Agent header when protection against cross-site request forgery (CSRF) is enabled for REST server by setting hbase.rest.csrf.enabled to true. If the incoming User-Agent matches any of these regular expressions, then the request is considered to be sent by a browser, and therefore CSRF prevention is enforced. If the request’s User-Agent does not match any of these regular expressions, then the request is considered to be sent by something other than a browser, such as scripted automation. In this case, CSRF is not a potential attack vector, so the prevention is not enforced. This helps achieve backwards-compatibility with existing automation that has not been updated to send the CSRF prevention header.
    "hbase.rest-csrf.browser-useragents-regex": string |*"Mozilla.,Opera."

    // If this setting is enabled and ACL based access control is active (the AccessController coprocessor is installed either as a system coprocessor or on a table as a table coprocessor) then you must grant all relevant users EXEC privilege if they require the ability to execute coprocessor endpoint calls. EXEC privilege, like any other permission, can be granted globally to a user, or to a user on a per table or per namespace basis. For more information on coprocessor endpoints, see the coprocessor section of the HBase online manual. For more information on granting or revoking permissions using the AccessController, see the security section of the HBase online manual.
    "hbase.security.exec.permission.checks": bool |*false

    // A comma-separated list of org.apache.hadoop.hbase.procedure.RegionServerProcedureManager procedure managers that are loaded by default on the active HRegionServer process. The lifecycle methods (init/start/stop) will be called by the active HRegionServer process to perform the specific globally barriered procedure. After implementing your own RegionServerProcedureManager, just put it in HBase’s classpath and add the fully qualified class name here.
    "hbase.procedure.regionserver.classes": string |*"none"

    // A comma-separated list of org.apache.hadoop.hbase.procedure.MasterProcedureManager procedure managers that are loaded by default on the active HMaster process. A procedure is identified by its signature and users can use the signature and an instant name to trigger an execution of a globally barriered procedure. After implementing your own MasterProcedureManager, just put it in HBase’s classpath and add the fully qualified class name here.
    "hbase.procedure.master.classes": string |*"none"

    // Fully qualified name of class implementing coordinated state manager.
    "hbase.coordinated.state.manager.class": string |*"org.apache.hadoop.hbase.coordination.ZkCoordinatedStateManager"

    // The period (in milliseconds) for refreshing the store files for the secondary regions. 0 means this feature is disabled. Secondary regions sees new files (from flushes and compactions) from primary once the secondary region refreshes the list of files in the region (there is no notification mechanism). But too frequent refreshes might cause extra Namenode pressure. If the files cannot be refreshed for longer than HFile TTL (hbase.master.hfilecleaner.ttl) the requests are rejected. Configuring HFile TTL to a larger value is also recommended with this setting.
    "hbase.regionserver.storefile.refresh.period": int |*0

    // Whether asynchronous WAL replication to the secondary region replicas is enabled or not. We have a separated implementation for replicating the WAL without using the general inter-cluster replication framework, so now we will not add any replication peers.
    "hbase.region.replica.replication.enabled": bool |*false

    // A comma separated list of class names. Each class in the list must extend org.apache.hadoop.hbase.http.FilterInitializer. The corresponding Filter will be initialized. Then, the Filter will be applied to all user facing jsp and servlet web pages. The ordering of the list defines the ordering of the filters. The default StaticUserWebFilter add a user principal as defined by the hbase.http.staticuser.user property.
    "hbase.http.filter.initializers": string |*"org.apache.hadoop.hbase.http.lib.StaticUserWebFilter"

    // This property if enabled, will check whether the labels in the visibility expression are associated with the user issuing the mutation
    "hbase.security.visibility.mutations.checkauths": bool |*false

    // The maximum number of threads that the HTTP Server will create in its ThreadPool.
    "hbase.http.max.threads": int |*16

    // Comma separated list of servlet names to enable for metrics collection. Supported servlets are jmx, metrics, prometheus
    "hbase.http.metrics.servlets": string |*"jmx,metrics,prometheus"

    // The codec that is to be used when replication is enabled so that the tags are also replicated. This is used along with HFileV3 which supports tags in them. If tags are not used or if the hfile version used is HFileV2 then KeyValueCodec can be used as the replication codec. Note that using KeyValueCodecWithTags for replication when there are no tags causes no harm.
    "hbase.replication.rpc.codec": string |*"org.apache.hadoop.hbase.codec.KeyValueCodecWithTags"

    // The maximum number of threads any replication source will use for shipping edits to the sinks in parallel. This also limits the number of chunks each replication batch is broken into. Larger values can improve the replication throughput between the master and slave clusters. The default of 10 will rarely need to be changed.
    "hbase.replication.source.maxthreads": int |*10

    // The user name to filter as, on static web filters while rendering content. An example use is the HDFS web UI (user to be used for browsing files).
    "hbase.http.staticuser.user": string |*"dr.stack"

    // The percent of region server RPC threads failed to abort RS. -1 Disable aborting; 0 Abort if even a single handler has died; 0.x Abort only when this percent of handlers have died; 1 Abort only all of the handers have died.
    "hbase.regionserver.handler.abort.on.error.percent": float |*0.5

    // Number of opened file handlers to cache. A larger value will benefit reads by providing more file handlers per mob file cache and would reduce frequent file opening and closing. However, if this is set too high, this could lead to a "too many opened file handlers" The default value is 1000.
    "hbase.mob.file.cache.size": int |*1000

    // The amount of time in seconds before the mob cache evicts cached mob files. The default value is 3600 seconds.
    "hbase.mob.cache.evict.period": int |*3600

    // The ratio (between 0.0 and 1.0) of files that remains cached after an eviction is triggered when the number of cached mob files exceeds the hbase.mob.file.cache.size. The default value is 0.5f.
    "hbase.mob.cache.evict.remain.ratio": string |*"0.5f"

    // The period that MobFileCleanerChore runs. The unit is second. The default value is one day. The MOB file name uses only the date part of the file creation time in it. We use this time for deciding TTL expiry of the files. So the removal of TTL expired files might be delayed. The max delay might be 24 hrs.
    "hbase.master.mob.cleaner.period": int |*86400

    // The max number of a MOB table regions that is allowed in a batch of the mob compaction. By setting this number to a custom value, users can control the overall effect of a major compaction of a large MOB-enabled table. Default is 0 - means no limit - all regions of a MOB table will be compacted at once
    "hbase.mob.major.compaction.region.batch.size": int |*0

    // The period that MobCompactionChore runs. The unit is second. The default value is one week.
    "hbase.mob.compaction.chore.period": int |*604800

    // Timeout for master for the snapshot procedure execution.
    "hbase.snapshot.master.timeout.millis": int |*300000

    // Timeout for regionservers to keep threads in snapshot request pool waiting.
    "hbase.snapshot.region.timeout": int |*300000

    // Number of rows in a batch operation above which a warning will be logged.
    "hbase.rpc.rows.warning.threshold": int |*5000

    // Default is 5 minutes. Make it 30 seconds for tests. See HBASE-19794 for some context.
    "hbase.master.wait.on.service.seconds": int |*30

    // Snapshot Cleanup chore interval in milliseconds. The cleanup thread keeps running at this interval to find all snapshots that are expired based on TTL and delete them.
    "hbase.master.cleaner.snapshot.interval": int |*1800000

    // Default Snapshot TTL to be considered when the user does not specify TTL while creating snapshot. Default value 0 indicates FOREVERE - snapshot should not be automatically deleted until it is manually deleted
    "hbase.master.snapshot.ttl": int |*0

    // Regions Recovery Chore interval in milliseconds. This chore keeps running at this interval to find all regions with configurable max store file ref count and reopens them.
    "hbase.master.regions.recovery.check.interval": int |*1200000

    // Very large number of ref count on a compacted store file indicates that it is a ref leak on that object(compacted store file). Such files can not be removed after it is invalidated via compaction. Only way to recover in such scenario is to reopen the region which can release all resources, like the refcount, leases, etc. This config represents Store files Ref Count threshold value considered for reopening regions. Any region with compacted store files ref count > this value would be eligible for reopening by master. Here, we get the max refCount among all refCounts on all compacted away store files that belong to a particular region. Default value -1 indicates this feature is turned off. Only positive integer value should be provided to enable this feature.
    "hbase.regions.recovery.store.file.ref.count": int |*-1

    // Default size of ringbuffer to be maintained by each RegionServer in order to store online slowlog responses. This is an in-memory ring buffer of requests that were judged to be too slow in addition to the responseTooSlow logging. The in-memory representation would be complete. For more details, please look into Doc Section: Get Slow Response Log from shell
    "hbase.regionserver.slowlog.ringbuffer.size": int |*256

    // Indicates whether RegionServers have ring buffer running for storing Online Slow logs in FIFO manner with limited entries. The size of the ring buffer is indicated by config: hbase.regionserver.slowlog.ringbuffer.size The default value is false, turn this on and get latest slowlog responses with complete data.
    "hbase.regionserver.slowlog.buffer.enabled": bool |*false

    // Should be enabled only if hbase.regionserver.slowlog.buffer.enabled is enabled. If enabled (true), all slow/large RPC logs would be persisted to system table hbase:slowlog (in addition to in-memory ring buffer at each RegionServer). The records are stored in increasing order of time. Operators can scan the table with various combination of ColumnValueFilter. More details are provided in the doc section: "Get Slow/Large Response Logs from System table hbase:slowlog"
    "hbase.regionserver.slowlog.systable.enabled": bool |*false

    // Maximum regions to merge at a time when we fix overlaps noted in CJ consistency report, but avoid merging 100 regions in one go!
    "hbase.master.metafixer.max.merge.count": int |*64

    // If value is true, RegionServer will abort batch requests of Put/Delete with number of rows in a batch operation exceeding threshold defined by value of config: hbase.rpc.rows.warning.threshold. The default value is false and hence, by default, only warning will be logged. This config should be turned on to prevent RegionServer from serving very large batch size of rows and this way we can improve CPU usages by discarding too large batch request.
    "hbase.rpc.rows.size.threshold.reject": bool |*false

    // Default values for NamedQueueService implementors. This comma separated full class names represent all implementors of NamedQueueService that we would like to be invoked by LogEvent handler service. One example of NamedQueue service is SlowLogQueueService which is used to store slow/large RPC logs in ringbuffer at each RegionServer. All implementors of NamedQueueService should be found under package: "org.apache.hadoop.hbase.namequeues.impl"
    "hbase.namedqueue.provider.classes": string |*"org.apache.hadoop.hbase.namequeues.impl.SlowLogQueueService,org.apache.hadoop.hbase.namequeues.impl.BalancerDecisionQueueService,org.apache.hadoop.hbase.namequeues.impl.BalancerRejectionQueueService,org.apache.hadoop.hbase.namequeues.WALEventTrackerQueueService"

    // Indicates whether active HMaster has ring buffer running for storing balancer decisions in FIFO manner with limited entries. The size of the ring buffer is indicated by config: hbase.master.balancer.decision.queue.size
    "hbase.master.balancer.decision.buffer.enabled": bool |*false

    // Indicates whether active HMaster has ring buffer running for storing balancer rejection in FIFO manner with limited entries. The size of the ring buffer is indicated by config: hbase.master.balancer.rejection.queue.size
    "hbase.master.balancer.rejection.buffer.enabled": bool |*false

    // If true, derive StoreFile locality metrics from the underlying DFSInputStream backing reads for that StoreFile. This value will update as the DFSInputStream’s block locations are updated over time. Otherwise, locality is computed on StoreFile open, and cached until the StoreFile is closed.
    "hbase.locality.inputstream.derive.enabled": bool |*false

    // If deriving StoreFile locality metrics from the underlying DFSInputStream, how long should the derived values be cached for. The derivation process may involve hitting the namenode, if the DFSInputStream’s block list is incomplete.
    "hbase.locality.inputstream.derive.cache.period": int |*60000
}
