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

#TaosParameter: {

// taosd configuration schema in CUE format

taosdConfig: {
    // compressMsgSize: whether to compress RPC messages
    // -1: no compression; 0: all messages; N > 0: only compress messages larger than N bytes
    // dynamic modification: supported, effective after restart
    // default value: -1
    // valid range: -1 - 100000000
    // supported since: v3.0.0.0
    compressMsgSize: int & >=-1 & <=100000000 | *-1

    // shellActivityTimer: heartbeat interval (in seconds) from client to mnode
    // dynamic modification: supported, immediate effect
    // default value: 3
    // valid range: 1 - 120
    // supported since: v3.0.0.0
    shellActivityTimer: int & >=1 & <=120 | *3

    // numOfRpcSessions: maximum number of RPC connections allowed
    // dynamic modification: supported, effective after restart
    // default value: 30000
    // valid range: 100 - 100000
    // supported since: v3.1.0.0
    numOfRpcSessions: int & >=100 & <=100000 | *30000

    // numOfRpcThreads: number of threads for RPC send/receive
    // dynamic modification: supported, effective after restart
    // default value: half of CPU cores
    // valid range: 1 - 50
    // supported since: v3.0.0.0
    numOfRpcThreads: int & >=1 & <=50

    // numOfTaskQueueThreads: number of threads for processing RPC messages
    // dynamic modification: supported, effective after restart
    // default value: half of CPU cores
    // valid range: 4 - 16
    // supported since: v3.0.0.0
    numOfTaskQueueThreads: int & >=4 & <=16

    // rpcQueueMemoryAllowed: max memory allowed for pending RPC messages (bytes)
    // dynamic modification: supported, immediate effect
    // default value: 1/10 of total system memory
    // valid range: 104857600 - INT64_MAX
    // supported since: v3.0.0.0
    rpcQueueMemoryAllowed: int & >=104857600 & <=9223372036854775807

    // resolveFQDNRetryTime: retry times when FQDN resolution fails
    // dynamic modification: not supported
    // default value: 100
    // valid range: 1 - 10240
    // removed since: v3.3.4.0
    resolveFQDNRetryTime: int & >=1 & <=10240 | *100

    // timeToGetAvailableConn: max wait time (ms) to get an available connection
    // dynamic modification: not supported
    // default value: 500000
    // valid range: 20 - 1000000
    // removed since: v3.3.4.0
    timeToGetAvailableConn: int & >=20 & <=1000000 | *500000

    // maxShellConns: maximum number of allowed connections
    // dynamic modification: not supported
    // default value: 50000
    // valid range: 10 - 50000000
    // removed since: v3.3.4.0
    maxShellConns: int & >=10 & <=50000000 | *50000

    // maxRetryWaitTime: max timeout (ms) for reconnection attempts
    // dynamic modification: supported, effective after restart
    // default value: 10000
    // valid range: 3000 - 86400000
    // supported since: v3.3.4.0
    maxRetryWaitTime: int & >=3000 & <=86400000 | *10000

    // shareConnLimit: number of requests a connection can share
    // dynamic modification: supported, effective after restart
    // default value: 10 (Linux/macOS), 1 (Windows)
    // valid range: 1 - 512
    // supported since: v3.3.4.0
    shareConnLimit: int & >=1 & <=512 | *(if os == "windows" then 1 else 10)

    // readTimeout: minimum timeout (seconds) for a single request
    // dynamic modification: supported, effective after restart
    // default value: 900
    // valid range: 64 - 604800
    // supported since: v3.3.4.0
    readTimeout: int & >=64 & <=604800 | *900

    // Monitoring related configurations
    // monitorInterval: monitorInterval (in seconds) for recording system metrics (CPU/memory)
    // dynamic modification: supported, immediate effect
    // default value: 30
    // valid range: 1 - 200000
    // supported since: v3.0.0.0
    monitorInterval: int & >=1 & <=200000 | *30

    // monitorMaxLogs: number of logs cached before uploading
    // dynamic modification: supported, immediate effect
    // default value: 100
    // valid range: 1 - 1000000
    // supported since: v3.0.0.0
    monitorMaxLogs: int & >=1 & <=1000000 | *100

    // monitorComp: whether to compress monitoring logs during upload
    // dynamic modification: supported, effective after restart
    // default value: 0
    // valid range: 0 - 1
    // supported since: v3.0.0.0
    monitorComp: int & >=0 & <=1 | *0

    // monitorLogProtocol: whether to print monitoring logs
    // dynamic modification: supported, immediate effect
    // default value: 0
    // valid range: 0 - 1
    // supported since: v3.3.0.0
    monitorLogProtocol: int & >=0 & <=1 | *0

    // monitorForceV2: whether to use V2 protocol for uploading logs
    // dynamic modification: supported, immediate effect
    // default value: 1
    // valid range: 0 - 1
    // supported since: v3.3.0.0
    monitorForceV2: int & >=0 & <=1 | *1

    // Telemetry related configurations
    // telemetryReporting: whether to upload telemetry data
    // dynamic modification: enterprise edition only, immediate effect
    // default value: 1
    // valid range: 0 - 1
    // supported since: v3.0.0.0
    telemetryReporting: int & >=0 & <=1 | *1

    // telemetryServer: address of the telemetry server
    // dynamic modification: not supported
    // default value: telemetry.taosdata.com
    // supported since: v3.0.0.0
    telemetryServer: string | *"telemetry.taosdata.com"

    // telemetryPort: port of the telemetry server
    // dynamic modification: not supported
    // default value: 80
    // valid range: 1 - 65056
    // supported since: v3.0.0.0
    telemetryPort: int & >=1 & <=65056 | *80

    // telemetryInterval: interval (seconds) for uploading telemetry data
    // dynamic modification: supported, immediate effect
    // default value: 86400
    // valid range: 1 - 200000
    // supported since: v3.0.0.0
    telemetryInterval: int & >=1 & <=200000 | *86400

    // crashReporting: whether to upload crash reports using V2 protocol
    // dynamic modification: supported, immediate effect
    // default value: 1
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    crashReporting: int & >=0 & <=1 | *1

    // countAlwaysReturnValue: whether COUNT/HYPERLOGLOG returns value when input is empty or NULL
    // 0: returns empty row; 1: no result for empty group/window if using INTERVAL or TSMA
    // dynamic modification: supported, immediate effect
    // default value: 1
    // valid range: 0 - 1
    // supported since: v3.0.0.0
    countAlwaysReturnValue: int & >=0 & <=1 | *1

    // tagFilterCache: whether to cache tag filter results
    // 0: disabled; 1: enabled
    // dynamic modification: not supported
    // default value: 0
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    tagFilterCache: int & >=0 & <=1 | *0

    // queryBufferSize: buffer size available for queries (in MB)
    // -1: unlimited
    // dynamic modification: supported, effective after restart
    // default value: -1
    // valid range: -1 - 500000000000
    // note: reserved parameter, not yet used in current version
    // supported since: v3.x.x.x
    queryBufferSize: int & >=-1 & <=500000000000 | *-1

    // queryRspPolicy: query response policy
    // 0: normal mode; 1: fast response mode (server responds immediately upon receiving the request)
    // dynamic modification: supported, immediate effect
    // default value: 0
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    queryRspPolicy: int & >=0 & <=1 | *0

    // queryUseMemoryPool: whether to use memory pool for query memory management
    // 0: disabled; 1: enabled (requires system memory >= 5GB and available >= 4GB)
    // dynamic modification: not supported
    // default value: 1
    // valid range: 0 - 1
    // supported since: v3.3.5.0
    queryUseMemoryPool: int & >=0 & <=1 | *1

    // minReservedMemorySize: minimum reserved system memory when memory pool is enabled (in MB)
    // dynamic modification: supported, immediate effect
    // default value: 20% of physical memory
    // valid range: 1024 - 1000000000
    // supported since: v3.3.5.0
    minReservedMemorySize: int & >=1024 & <=1000000000 | *"20% of physical memory"

    // singleQueryMaxMemorySize: max memory allowed per query on a dnode (in MB)
    // 0: no limit
    // dynamic modification: not supported
    // default value: 0
    // valid range: 0 - 1000000000
    // supported since: v3.3.5.0
    singleQueryMaxMemorySize: int & >=0 & <=1000000000 | *0

    // filterScalarMode: force scalar filtering mode
    // 0: disabled; 1: enabled
    // dynamic modification: not supported
    // default value: 0
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    filterScalarMode: int & >=0 & <=1 | *0

    // queryNoFetchTimeoutSec: timeout (seconds) when application does not fetch data for long time
    // internal parameter
    // dynamic modification: enterprise edition only, immediate effect
    // default value: 18000
    // valid range: 60 - 1000000000
    // supported since: v3.1.0.0
    queryNoFetchTimeoutSec: int & >=60 & <=1000000000 | *18000

    // queryPlannerTrace: whether to output detailed query plan logs
    // internal parameter
    // dynamic modification: supported, immediate effect
    // default value: 0
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    queryPlannerTrace: int & >=0 & <=1 | *0

    // queryNodeChunkSize: chunk size for query plan (in bytes)
    // internal parameter
    // dynamic modification: supported, immediate effect
    // default value: 32768 (32KB)
    // valid range: 1024 - 131072 (128KB)
    // supported since: v3.1.0.0
    queryNodeChunkSize: int & >=1024 & <=131072 | *32768

    // queryUseNodeAllocator: memory allocation method for query plan
    // internal parameter
    // dynamic modification: supported, immediate effect
    // default value: 1
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    queryUseNodeAllocator: int & >=0 & <=1 | *1

    // queryMaxConcurrentTables: maximum number of tables that can be queried concurrently
    // internal parameter
    // dynamic modification: not supported
    // default value: 200
    // valid range: INT64_MIN - INT64_MAX
    // supported since: v3.1.0.0
    queryMaxConcurrentTables: int | *200

    // queryRsmaTolerance: tolerance for RSMA query plans
    // internal parameter
    // dynamic modification: not supported
    // default value: 1000
    // valid range: 0 - 900000
    // supported since: v3.1.0.0
    queryRsmaTolerance: int & >=0 & <=900000 | *1000

    // enableQueryHb: whether to send heartbeat during query execution
    // internal parameter
    // dynamic modification: supported, immediate effect
    // default value: 1
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    enableQueryHb: int & >=0 & <=1 | *1

    // pqSortMemThreshold: memory threshold for sorting operations (in MB)
    // internal parameter
    // dynamic modification: not supported
    // default value: 16
    // valid range: 1 - 10240
    // supported since: v3.1.0.0
    pqSortMemThreshold: int & >=1 & <=10240 | *16

    // timezone: timezone setting
    // dynamic modification: not supported
    // default value: system timezone
    // supported since: v3.1.0.0
    timezone?: string

    // locale: system locale and encoding
    // dynamic modification: not supported
    // default value: system locale
    // supported since: v3.1.0.0
    locale?: string

    // charset: character set encoding
    // dynamic modification: not supported
    // default value: system charset
    // supported since: v3.1.0.0
    charset?: string

    // dataDir: directory where all data files are stored
    // dynamic modification: not supported
    // default value: /var/lib/taos
    // supported since: v3.1.0.0
    dataDir: string | *"/var/lib/taos"

    // diskIDCheckEnabled: whether to check disk ID when restarting dnode
    // 0: check; 1: do not check
    // dynamic modification: not supported
    // default value: 1
    // valid range: 0 - 1
    // supported since: v3.3.5.0
    diskIDCheckEnabled: int & >=0 & <=1 | *1

    // tempDir: directory for temporary system files
    // dynamic modification: not supported
    // default value: /tmp
    // supported since: v3.1.0.0
    tempDir: string | *"/tmp"

    // minimalDataDirGB: minimum space required in dataDir (in GB)
    // dynamic modification: not supported
    // default value: 2
    // valid range: 0.001 - 10000000
    // supported since: v3.1.0.0
    minimalDataDirGB: number & >=0.001 & <=10000000 | *2

    // minimalTmpDirGB: minimum space required in tempDir (in GB)
    // dynamic modification: not supported
    // default value: 1
    // valid range: 0.001 - 10000000
    // supported since: v3.1.0.0
    minimalTmpDirGB: number & >=0.001 & <=10000000 | *1

    // cacheLazyLoadThreshold: threshold for lazy loading cache
    // internal parameter
    // dynamic modification: enterprise edition only, immediate effect
    // default value: 500
    // valid range: 0 - 100000
    // supported since: v3.1.0.0
    cacheLazyLoadThreshold: int & >=0 & <=100000 | *500

    // supportVnodes: max number of vnodes supported by a dnode
    // enterprise edition only
    // dynamic modification: enterprise only, immediate effect
    // default value: 2 * CPU cores + 5
    // valid range: 0 - 4096
    // supported since: v3.1.0.0
    supportVnodes: int & >=0 & <=4096

    // numOfCommitThreads: maximum number of disk flush threads
    // dynamic modification: supported, effective after restart
    // default value: 4
    // valid range: 1 - 1024
    // supported since: v3.1.0.0
    numOfCommitThreads: int & >=1 & <=1024 | *4

    // numOfCompactThreads: maximum number of compaction threads
    // dynamic modification: supported, effective after restart
    // default value: 2
    // valid range: 1 - 16
    // supported since: v3.1.0.0
    numOfCompactThreads: int & >=1 & <=16 | *2

    // numOfMnodeReadThreads: read threads for mnode
    // dynamic modification: supported, effective after restart
    // default value: 1/4 of CPU cores (min 1, max 4)
    // valid range: 0 - 1024
    // supported since: v3.1.0.0
    numOfMnodeReadThreads: int & >=0 & <=1024

    // numOfVnodeQueryThreads: query threads for vnode
    // dynamic modification: supported, effective after restart
    // default value: 2 * CPU cores (min 16)
    // valid range: 0 - 1024
    // supported since: v3.1.0.0
    numOfVnodeQueryThreads: int & >=0 & <=1024

    // numOfVnodeFetchThreads: fetch threads for vnode
    // dynamic modification: supported, effective after restart
    // default value: 1/4 of CPU cores (min 4)
    // valid range: 0 - 1024
    // supported since: v3.1.0.0
    numOfVnodeFetchThreads: int & >=0 & <=1024

    // numOfVnodeRsmaThreads: rsma threads for vnode
    // dynamic modification: supported, effective after restart
    // default value: 1/4 of CPU cores (min 4)
    // valid range: 0 - 1024
    // supported since: v3.1.0.0
    numOfVnodeRsmaThreads: int & >=0 & <=1024

    // numOfQnodeQueryThreads: query threads for qnode
    // dynamic modification: supported, effective after restart
    // default value: 2 * CPU cores (min 16)
    // valid range: 0 - 1024
    // supported since: v3.1.0.0
    numOfQnodeQueryThreads: int & >=0 & <=1024

    // numOfSnodeSharedThreads: shared threads for snode
    // dynamic modification: supported, effective after restart
    // default value: 1/4 of CPU cores (min 2, max 4)
    // valid range: 0 - 1024
    // supported since: v3.1.0.0
    numOfSnodeSharedThreads: int & >=0 & <=1024

    // numOfSnodeUniqueThreads: unique threads for snode
    // dynamic modification: supported, effective after restart
    // default value: 1/4 of CPU cores (min 2, max 4)
    // valid range: 0 - 1024
    // supported since: v3.1.0.0
    numOfSnodeUniqueThreads: int & >=0 & <=1024

    // ratioOfVnodeStreamThreads: proportion of stream threads in vnode
    // dynamic modification: supported, effective after restart
    // default value: 0.5
    // valid range: 0.01 - 4
    // supported since: v3.1.0.0
    ratioOfVnodeStreamThreads: number & >=0.01 & <=4 | *0.5

    // ttlUnit: unit of TTL in seconds
    // dynamic modification: supported, immediate effect
    // default value: 86400
    // valid range: 1 - 31572500
    // supported since: v3.1.0.0
    ttlUnit: int & >=1 & <=31572500 | *86400

    // ttlPushInterval: interval to check expired data
    // enterprise edition only
    // dynamic modification: enterprise only, immediate effect
    // default value: 10
    // valid range: 1 - 100000
    // supported since: v3.1.0.0
    ttlPushInterval: int & >=1 & <=100000 | *10

    // ttlChangeOnWrite: whether write operations reset TTL timer
    // dynamic modification: supported, immediate effect
    // default value: 0
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    ttlChangeOnWrite: int & >=0 & <=1 | *0

    // ttlBatchDropNum: number of sub-tables dropped per batch
    // enterprise edition only
    // dynamic modification: enterprise only, immediate effect
    // default value: 10000
    // valid range: 0 - 2147483647
    // supported since: v3.1.0.0
    ttlBatchDropNum: int & >=0 & <=2147483647 | *10000

    // retentionSpeedLimitMB: speed limit for data migration between storage tiers
    // dynamic modification: supported, immediate effect
    // default value: 0 (unlimited)
    // valid range: 0 - 1024
    // supported since: v3.1.0.0
    retentionSpeedLimitMB: int & >=0 & <=1024 | *0

    // maxTsmaNum: max number of TSMA objects allowed in cluster
    // dynamic modification: supported, immediate effect
    // default value: 0
    // valid range: 0 - 3
    // supported since: v3.1.0.0
    maxTsmaNum: int & >=0 & <=3 | *0

    // tmqMaxTopicNum: max number of topics allowed in TMQ
    // enterprise edition only
    // dynamic modification: enterprise only, immediate effect
    // default value: 20
    // valid range: 1 - 10000
    // supported since: v3.1.0.0
    tmqMaxTopicNum: int & >=1 & <=10000 | *20

    // tmqRowSize: max number of records per block in TMQ
    // enterprise edition only
    // dynamic modification: enterprise only, immediate effect
    // default value: 4096
    // valid range: 1 - 1000000
    // supported since: v3.1.0.0
    tmqRowSize: int & >=1 & <=1000000 | *4096


    // syncLogBufferMemoryAllowed: max memory allowed for sync log buffer (bytes)
    // enterprise edition only
    // dynamic modification: enterprise only, immediate effect
    // default value: 1/10 of server memory
    // valid range: 104857600 - 9223372036854775807
    // supported since: v3.1.3.2 / v3.3.2.13
    syncLogBufferMemoryAllowed: int & >=104857600 & <=9223372036854775807

    // syncElectInterval: internal parameter for sync module debugging
    // dynamic modification: not supported
    // supported since: v3.1.0.0
    syncElectInterval?: int

    // syncHeartbeatInterval: internal parameter for sync module debugging
    // dynamic modification: not supported
    // supported since: v3.1.0.0
    syncHeartbeatInterval?: int

    // syncHeartbeatTimeout: internal parameter for sync module debugging
    // dynamic modification: not supported
    // supported since: v3.1.0.0
    syncHeartbeatTimeout?: int

    // syncSnapReplMaxWaitN: internal parameter for sync module debugging
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    syncSnapReplMaxWaitN?: int

    // arbHeartBeatIntervalSec: internal parameter for sync module debugging
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    arbHeartBeatIntervalSec?: int

    // arbCheckSyncIntervalSec: internal parameter for sync module debugging
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    arbCheckSyncIntervalSec?: int

    // arbSetAssignedTimeoutSec: internal parameter for sync module debugging
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    arbSetAssignedTimeoutSec?: int

    // arbSetAssignedTimeoutSec: internal parameter for mnode module debugging
    // duplicate key from above; assuming same field used in different context
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    arbSetAssignedTimeoutSec?: int

    // mndLogRetention: internal parameter for mnode module debugging
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    mndLogRetention?: int

    // skipGrant: internal parameter for authorization check
    // dynamic modification: not supported
    // supported since: v3.1.0.0
    skipGrant?: int

    // trimVDbIntervalSec: interval to delete expired data
    // enterprise edition only
    // dynamic modification: enterprise only, immediate effect
    // supported since: v3.1.0.0
    trimVDbIntervalSec?: int

    // ttlFlushThreshold: frequency of TTL timer
    // enterprise edition only
    // dynamic modification [ ](c)
    ttlFlushThreshold: int

    // compactPullupInterval: frequency of data compaction timer
    // enterprise edition only
    // dynamic modification: enterprise only, immediate effect
    // supported since: v3.1.0.0
    compactPullupInterval?: int

    // walFsyncDataSizeLimit: threshold for WAL fsync
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    walFsyncDataSizeLimit?: int

    // transPullupInterval: retry interval for mnode transactions
    // enterprise edition only
    // dynamic modification: enterprise only, immediate effect
    // supported since: v3.1.0.0
    transPullupInterval?: int

    // forceKillTrans: internal parameter for mnode transaction debugging
    // dynamic modification: supported, immediate effect
    // supported since: v3.3.7.0
    forceKillTrans?: int

    // mqRebalanceInterval: consumer rebalance interval
    // enterprise edition only
    // dynamic modification: enterprise only, immediate effect
    // supported since: v3.1.0.0
    mqRebalanceInterval?: int

    // uptimeInterval: interval to record system uptime
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    uptimeInterval?: int

    // timeseriesThreshold: internal parameter for usage statistics
    // enterprise edition only
    // dynamic modification: enterprise only, immediate effect
    // supported since: v3.1.0.0
    timeseriesThreshold?: int

    // enableStrongPassword: require strong password format
    // dynamic modification: supported, effective after restart
    // default value: 1
    // valid range: 0 - 1
    // supported since: v3.3.6.0
    enableStrongPassword: int & >=0 & <=1 | *1

    // udf: enable/disable UDF service
    // dynamic modification: supported, effective after restart
    // default value: 0
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    udf: int & >=0 & <=1 | *0

    // udfdResFuncs: reserved internal parameter
    // dynamic modification: supported, effective after restart
    udfdResFuncs?: string

    // udfdLdLibPath: library path for UDF
    // dynamic modification: supported, effective after restart
    udfdLdLibPath?: string

    // disableStream: enable/disable stream computation
    // enterprise edition only
    // dynamic modification: enterprise only, effective after restart
    // default value: 0
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    disableStream: int & >=0 & <=1 | *0

    // streamBufferSize: buffer size for window state in memory
    // dynamic modification: supported, effective after restart
    // default value: 128 * 1024 * 1024 bytes
    // valid range: 0 - 9223372036854775807
    // supported since: v3.1.0.0
    streamBufferSize: int & >=0 & <=9223372036854775807 | *134217728

    // checkpointInterval: checkpoint synchronization interval
    // enterprise edition only
    // dynamic modification: enterprise only, effective after restart
    // supported since: v3.1.0.0
    checkpointInterval?: int

    // concurrentCheckpoint: enable concurrent checkpointing
    // enterprise edition only
    // dynamic modification: enterprise only, immediate effect
    // supported since: v3.1.0.0
    concurrentCheckpoint?: int

    // maxStreamBackendCache: maximum backend cache size for stream
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    maxStreamBackendCache?: int

    // streamSinkDataRate: control write speed of stream results
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    streamSinkDataRate?: int

    // streamNotifyMessageSize: message size for event notification (KB)
    // default value: 8192
    // valid range: 8 - 1048576
    // supported since: v3.3.6.0
    streamNotifyMessageSize: int & >=8 & <=1048576 | *8192

    // streamNotifyFrameSize: frame size for event notifications (KB)
    // default value: 256
    // valid range: 8 - 1048576
    // supported since: v3.3.6.0
    streamNotifyFrameSize: int & >=8 & <=1048576 | *256

    // adapterFqdn: FQDN for taosAdapter service
    // default value: localhost
    // dynamic modification: not supported
    // supported since: v3.3.6.0
    adapter: string | *"localhost"

    // adapterPort: port for taosAdapter service
    // default value: 6041
    // valid range: 1 - 65056
    // dynamic modification: not supported
    // supported since: v3.3.6.0
    adapterPort: int & >=1 & <=65056 | *6041

    // adapterToken: base64 encoded {username}:{password}
    // default value: cm9vdDp0YW9zZGF0YQ==
    // dynamic modification: not supported
    // supported since: v3.3.6.0
    adapterToken: string | *"cm9vdDp0YW9zZGF0YQ=="

    // logDir: directory where logs are written
    // default value: /var/log/taos
    // dynamic modification: not supported
    // supported since: v3.1.0.0
    logDir: string | *"/var/log/taos"

    // minimalLogDirGB: minimum space required for log directory
    // dynamic modification: not supported
    // default value: 1
    // valid range: 0.001 - 10000000
    // supported since: v3.1.0.0
    minimalLogDirGB: number & >=0.001 & <=10000000 | *1

    // numOfLogLines: max lines per log file
    // enterprise edition only
    // dynamic modification: enterprise only, immediate effect
    // default value: 10,000,000
    // valid range: 1000 - 2000000000
    // supported since: v3.1.0.0
    numOfLogLines: int & >=1000 & <=2000000000 | *10000000

    // asyncLog: logging mode (0: sync, 1: async)
    // dynamic modification: supported, immediate effect
    // default value: 1
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    asyncLog: int & >=0 & <=1 | *1

    // logKeepDays: maximum days to keep logs
    // negative value means -logKeepDays days and behavior same as positive
    // dynamic modification: enterprise only, immediate effect
    // default value: 0
    // valid range: -365000 - 365000
    // supported since: v3.1.0.0
    logKeepDays: int & >=-365000 & <=365000 | *0

    // slowLogThreshold: threshold for slow queries (seconds)
    // dynamic modification: supported, immediate effect
    // default value: 3
    // valid range: 1 - 2147483647
    // supported since: v3.3.0.0
    slowLogThreshold: int & >=1 & <=2147483647 | *3

    // slowLogMaxLen: max length of slow query log entry
    // dynamic modification: supported, immediate effect
    // default value: 4096
    // valid range: 1 - 16384
    // supported since: v3.3.0.0
    slowLogMaxLen: int & >=1 & <=16384 | *4096

    // slowLogScope: types of queries to log (ALL/QUERY/INSERT/OTHERS/NONE)
    // dynamic modification: supported, immediate effect
    // default value: QUERY
    // supported since: v3.3.0.0
    slowLogScope: "ALL" | "QUERY" | "INSERT" | "OTHERS" | "NONE" | *"QUERY"

    // slowLogExceptDb: database name excluded from slow query logging
    // dynamic modification: supported, immediate effect
    // supported since: v3.3.0.0
    slowLogExceptDb?: string

    // debugFlag: global log level switch
    // values: 131(ERROR/WARN), 135(DEBUG), 143(TRACE)
    // dynamic modification: supported, immediate effect
    // default value: 131 or 135 (depends on module)
    // supported since: v3.1.0.0
    debugFlag: int & (131 | 135 | 143) | *(131 | 135)

    // tmrDebugFlag: timer module log level
    // supported since: v3.1.0.0
    tmrDebugFlag: int & (131 | 135 | 143) | *131

    // uDebugFlag: common utility module log level
    // supported since: v3.1.0.0
    uDebugFlag: int & (131 | 135 | 143) | *131

    // rpcDebugFlag: RPC module log level
    // supported since: v3.1.0.0
    rpcDebugFlag: int & (131 | 135 | 143) | *131

    // qDebugFlag: query module log level
    // supported since: v3.1.0.0
    qDebugFlag: int & (131 | 135 | 143) | *131

    // dDebugFlag: dnode module log level
    // supported since: v3.1.0.0
    dDebugFlag: int & (131 | 135 | 143) | *131

    // vDebugFlag: vnode module log level
    // supported since: v3.1.0.0
    vDebugFlag: int & (131 | 135 | 143) | *131

    // mDebugFlag: mnode module log level
    // supported since: v3.1.0.0
    mDebugFlag: int & (131 | 135 | 143) | *131

    // azDebugFlag: S3/AZ module log level
    // supported since: v3.3.4.3
    azDebugFlag: int & (131 | 135 | 143) | *131

    // sDebugFlag: sync module log level
    // supported since: v3.1.0.0
    sDebugFlag: int & (131 | 135 | 143) | *131

    // tsdbDebugFlag: tsdb module log level
    // supported since: v3.1.0.0
    tsdbDebugFlag: int & (131 | 135 | 143) | *131

    // tqDebugFlag: tq module log level
    // supported since: v3.1.0.0
    tqDebugFlag: int & (131 | 135 | 143) | *131

    // fsDebugFlag: filesystem module log level
    // supported since: v3.1.0.0
    fsDebugFlag: int & (131 | 135 | 143) | *131

    // udfDebugFlag: UDF module log level
    // supported since: v3.1.0.0
    udfDebugFlag: int & (131 | 135 | 143) | *131

    // smaDebugFlag: SMA module log level
    // supported since: v3.1.0.0
    smaDebugFlag: int & (131 | 135 | 143) | *131

    // idxDebugFlag: index module log level
    // supported since: v3.1.0.0
    idxDebugFlag: int & (131 | 135 | 143) | *131

    // tdbDebugFlag: TDB module log level
    // supported since: v3.1.0.0
    tdbDebugFlag: int & (131 | 135 | 143) | *131

    // metaDebugFlag: metadata module log level
    // supported since: v3.1.0.0
    metaDebugFlag: int & (131 | 135 | 143) | *131

    // stDebugFlag: stream module log level
    // supported since: v3.1.0.0
    stDebugFlag: int & (131 | 135 | 143) | *131

    // sndDebugFlag: snode module log level
    // supported since: v3.1.0.0
    sndDebugFlag: int & (131 | 135 | 143) | *131

    // enableCoreFile: whether to generate core file on crash
    // dynamic modification: supported, immediate effect
    // default value: 1
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    enableCoreFile: int & >=0 & <=1 | *1

    // configDir: directory of configuration files
    // dynamic modification: not supported
    // supported since: v3.1.0.0
    configDir?: string

    // forceReadConfig: use config from file or persisted values
    // 0: use persisted config; 1: use config file
    // dynamic modification: not supported
    // default value: 0
    // valid range: 0 - 1
    // supported since: v3.3.5.0
    forceReadConfig?: int & >=0 & <=1 | *0

    // scriptDir: directory for test scripts
    // dynamic modification: not supported
    // supported since: v3.1.0.0
    scriptDir?: string

    // assert: enable/disable assertion checking
    // dynamic modification: not supported
    // default value: 0
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    assert?: int & >=0 & <=1 | *0

    // randErrorChance: chance of random failure (for testing)
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    randErrorChance?: int

    // randErrorDivisor: divisor for random failure (for testing)
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    randErrorDivisor?: int

    // randErrorScope: scope of random failure injection (for testing)
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    randErrorScope?: int

    // safetyCheckLevel: internal parameter for safety checks
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    safetyCheckLevel?: int

    // experimental: enable experimental features
    // dynamic modification: supported, immediate effect
    // supported since: v3.1.0.0
    experimental?: int

    // simdEnable: enable SIMD acceleration
    // dynamic modification: not supported
    // supported since: v3.3.4.3
    simdEnable?: int & >=0 & <=1

    // AVX512Enable: enable AVX512 acceleration
    // dynamic modification: not supported
    // supported since: v3.3.4.3
    AVX512Enable?: int & >=0 & <=1

    // rsyncPort: port used for stream computing debugging
    // dynamic modification: not supported
    // supported since: v3.1.0.0
    rsyncPort?: int

    // snodeAddress: address for stream computing debugging
    // dynamic modification: supported, effective after restart
    // supported since: v3.1.0.0
    snodeAddress?: string

    // checkpointBackupDir: directory for snode recovery data
    // dynamic modification: supported, effective after restart
    // supported since: v3.1.0.0
    checkpointBackupDir?: string

    // enableAuditDelete: enable audit log for delete operations
    // dynamic modification: not supported
    // supported since: v3.1.0.0
    enableAuditDelete?: int & >=0 & <=1

    // slowLogThresholdTest: threshold for slow log testing
    // dynamic modification: not supported
    // supported since: v3.1.0.0
    slowLogThresholdTest?: int

    // bypassFlag: control write bypass behavior
    // values:
    //   0: normal write
    //   1: return before sending RPC
    //   2: return after receiving RPC
    //   4: return before writing to cache
    //   8: return before persisting to disk
    // dynamic modification: supported, immediate effect
    // supported since: v3.3.4.5
    bypassFlag: int & (0 | 1 | 2 | 4 | 8) | *0


    // fPrecision: float compression precision threshold
    // values smaller than this will have their mantissa truncated
    // dynamic modification: supported, immediate effect
    // default value: 0.00000001
    // valid range: 0.00000001 - 0.1
    // supported since: v3.1.0.0
    fPrecision: number & >=0.00000001 & <=0.1 | *0.00000001

    // dPrecision: double compression precision threshold
    // values smaller than this will have their mantissa truncated
    // dynamic modification: supported, immediate effect
    // default value: 0.0000000000000001
    // valid range: 0.0000000000000001 - 0.1
    // supported since: v3.1.0.0
    dPrecision: number & >=0.0000000000000001 & <=0.1 | *0.0000000000000001

    // lossyColumn: enable TSZ lossy compression for float/double/none
    // valid values: "float", "double", "none"
    // default value: "none"
    // dynamic modification: not supported
    // supported since: v3.1.0.0
    // deprecated since: v3.3.0.0
    lossyColumn: "float" | "double" | "none" | *"none"

    // ifAdtFse: use FSE instead of HUFFMAN in TSZ lossy compression
    // 0: off, 1: on
    // dynamic modification: supported, effective after restart
    // default value: 0
    // valid range: 0 - 1
    // supported since: v3.1.0.0
    // deprecated since: v3.3.0.0
    ifAdtFse: int & >=0 & <=1 | *0

    // enableIpv6: enable IPv6 communication between nodes
    // dynamic modification: not supported
    // supported since: v3.3.7.0
    enableIpv6?: int & >=0 & <=1

    // maxRange: internal parameter for lossy compression
    // dynamic modification: supported, effective after restart
    // supported since: v3.1.0.0
    // deprecated since: v3.3.0.0
    maxRange?: int

    // curRange: internal parameter for lossy compression
    // dynamic modification: supported, effective after restart
    // supported since: v3.1.0.0
    // deprecated since: v3.3.0.0
    curRange?: int

    // compressor: internal parameter for lossy compression
    // dynamic modification: supported, effective after restart
    // supported since: v3.1.0.0
    // deprecated since: v3.3.0.0
    compressor?: int
}

configuration: #TaosParameter & {
}
