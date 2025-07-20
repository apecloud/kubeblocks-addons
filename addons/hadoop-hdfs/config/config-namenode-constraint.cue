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

#NameNodeParameter: {
	// Cluster
	"dfs.nameservices"?: string | "{{- .KB_CLUSTER_NAME }}"

	// DFS NameNode在本地文件系统存储事务(edits)文件的位置。默认值同dfs.namenode.name.dir的默认值
	"dfs.namenode.edits.dir": string | *"/hadoop/dfs/metadata"

	// DFS NameNode在本地文件系统存储fsimage的目录，默认值/hadoop/dfs/metadata
	"dfs.namenode.name.dir": string | *"/hadoop/dfs/metadata"

	// 是否让NameNode尝试恢复失败的dfs.namenode.name.dir。默认值true，取值范围true或false
	"dfs.namenode.name.dir.restore": bool | *true

	// 执行Balancer时，字节数小于该参数值的块将不会被移动（单位：字节）。默认值10485760，取值范围大于0
	"dfs.balancer.getBlocks.min-block-size": int | *10485760

	// 在Balancer中，从NameNode获取源DataNode的块列表时，所获取的所有块的总大小 (单位：字节)。默认值2147483648，取值范围大于1073741824
	"dfs.balancer.getBlocks.size": int & >=1073741824 | *2147483648

	// 执行Balancer时，每次迭代移动的最大字节数。默认值32212254720，取值范围大于1073741824
	"dfs.balancer.max-size-to-move": int & >=1073741824 | *32212254720

	// 指定NameNode扫描DataNode待删除块的最大数量及向DataNode发送的待删除块数量。默认值10000，取值范围100~1000000
	"dfs.block.invalidate.limit": int & >=100 & <=1000000 | *10000

	// 选择EC文件的块放置DataNode策略。默认值org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyRackFaultTolerant
	"dfs.block.placement.ec.classname": string & ("org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyDefault" | "org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyWithRackGroup" | "org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyWithNodeLabel" | "org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyWithNodeGroup" | "org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyWithNonAffinityNodeGroup" | "org.apache.hadoop.hdfs.server.blockmanagement.AvailableSpaceBlockPlacementPolicy" | "org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyRackFaultTolerant" | "org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyWithAZExpression") | *"org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyRackFaultTolerant"

	// 选择副本放置DataNode策略。默认值org.apache.hadoop.hdfs.server.blockmanagement.AvailableSpaceBlockPlacementPolicy
	"dfs.block.replicator.classname": string & ("org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyDefault" | "org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyWithRackGroup" | "org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyWithNodeLabel" | "org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyWithNodeGroup" | "org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyWithNonAffinityNodeGroup" | "org.apache.hadoop.hdfs.server.blockmanagement.AvailableSpaceBlockPlacementPolicy" | "org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyRackFaultTolerant" | "org.apache.hadoop.hdfs.server.blockmanagement.BlockPlacementPolicyWithAZExpression") | *"org.apache.hadoop.hdfs.server.blockmanagement.AvailableSpaceBlockPlacementPolicy"

	// 每个校验和的字节数，不能大于dfs.stream-buffer-size值且必须能被dfs.blocksize值整除。默认值512，取值范围大于0
	"dfs.bytes-per-checksum": int & >=1 | *512

	// 读取EC文件的并发线程数。默认值256，取值范围大于16
	"dfs.client.read.striped.threadpool.size": int & >=16 | *256

	// 禁止移动写入指定DataNode上的数据块，默认为false。进行Balancer或Mover时，colocation写入的文件不会被移动
	"dfs.datanode.block-pinning.enabled": bool | *false

	// 设置DataNode向NameNode发送Lifeline协议消息的时间间隔。单位：秒，值必须大于dfs.heartbeat.interval的值
	"dfs.datanode.lifeline.interval.seconds"?: int

	// 设置磁盘均衡操作时磁盘存储量与理想状态的差异阈值，默认值10，取值范围1~100
	"dfs.disk.balancer.block.tolerance.percent": int & >=1 & <=100 | *10

	// 设置数据移动过程中容忍的最大错误次数，超过此阈值则移动失败，默认值5，取值范围大于0
	"dfs.disk.balancer.max.disk.errors": int & >=1 | *5

	// 设置Disk Balancer特性传输数据时使用的最大磁盘带宽，单位：MB/s，默认值10，取值范围大于0
	"dfs.disk.balancer.max.disk.throughputInMBperSec": int & >=1 | *10

	// 设置两磁盘之间数据密度域值差的容忍阈值，超过此值则需要数据均衡，默认值10，取值范围1~100
	"dfs.disk.balancer.plan.threshold.percent": int & >=1 & <=100 | *10

	// 备用节点连接主用节点进行edit日志拆分的时间间隔，单位：秒，默认值120，取值范围0~86400
	"dfs.ha.log-roll.period": int & <=86400 | *120

	// 备用节点检查共享edit日志的时间间隔，单位：毫秒，默认值60000，取值范围0~864000
	"dfs.ha.tail-edits.period": int & <=864000 | *60000

	// DataNode向NameNode发送心跳的时间间隔，单位：秒，默认值10，取值范围3~180
	"dfs.heartbeat.interval": int & >=3 & <=180 | *10

	// 是否压缩fsimage，默认值false，取值范围true或false
	"dfs.image.compress": bool | *false

	// 设置fsimage压缩的codec，默认值org.apache.hadoop.io.compress.DefaultCodec
	"dfs.image.compression.codec": string & ("none" | "org.apache.hadoop.io.compress.BZip2Codec" | "org.apache.hadoop.io.compress.DefaultCodec" | "org.apache.hadoop.io.compress.DeflateCodec" | "org.apache.hadoop.io.compress.Lz4Codec" | "org.apache.hadoop.io.compress.SnappyCodec" | "org.apache.hadoop.io.compress.GzipCodec" | "org.apache.hadoop.io.compress.ZStandardCodec") | *"org.apache.hadoop.io.compress.DefaultCodec"

	// fsimage包含的inode数量少于该阈值时不生成sub-section，禁用并行加载特性，默认值1000000
	"dfs.image.parallel.inode.threshold": int & >=1 | *1000000

	// 是否启用fsimage并行加载特性，默认值true，取值范围true或false
	"dfs.image.parallel.load": bool | *true

	// 生成fsimage时将一个section分解为多少个sub-section，默认值100
	"dfs.image.parallel.target.sections": int & >=1 | *100

	// 并行加载的线程数量，默认值50，取值范围大于等于1
	"dfs.image.parallel.threads": int & >=1 | *50

	// fsimage传输带宽，单位：B/s，默认值104857600，取值范围0~1073741824
	"dfs.image.transfer.bandwidthPerSec": int & <=1073741824 | *104857600

	// fsimage传输超时时间，单位：毫秒，默认值600000，取值范围1~3600000
	"dfs.image.transfer.timeout": int & >=1 & <=3600000 | *600000

	// HDFS文件访问时间精确到该值，默认值3600000，取值范围大于等于0
	"dfs.namenode.accesstime.precision": int | *3600000

	// 是否启用HDFS ACL，默认值true，取值范围true或false
	"dfs.namenode.acls.enabled": bool | *true

	// 是否启用异步审计日志，默认值false，取值范围true或false
	"dfs.namenode.audit.log.async": bool | *false

	// 审计日志命令列表，默认值"open,getfileinfo,getAclStatus"
	"dfs.namenode.audit.log.debug.cmdlist": string | *"open,getfileinfo,getAclStatus"

	// 是否优先选择客户端所在节点的DataNode，默认值false
	"dfs.namenode.available-space-block-placement-policy.balance-local-node": bool | *false

	// 控制新块分配到拥有更多可用磁盘空间的DataNode的比例，默认值0.6，取值范围0~1
	"dfs.namenode.available-space-block-placement-policy.balanced-space-preference-fraction": number | *0.6

	// 是否避免写入失效DataNode，默认值true，取值范围true或false
	"dfs.namenode.avoid.write.stale.datanode": bool | *true

	// 增量删除块的数量，默认值1000，取值范围大于等于1
	"dfs.namenode.block.deletion.increment": int & >=1 | *1000

	// 备NameNode每隔dfs.namenode.checkpoint.check.period秒轮询查询未检查点的事务，默认值60，取值范围0~86400
	"dfs.namenode.checkpoint.check.period": int & <=86400 | *60

	// 两个检查点间的时间间隔，单位：秒，默认值3600
	"dfs.namenode.checkpoint.period": int | *360

	// 让备NameNode或检查点节点创建检查点的事务数，无论"dfs.namenode.checkpoint.period"是否到达。默认值5000000，取值范围1~10000000000
	"dfs.namenode.checkpoint.txns": int & >=1 & <=10000000000 | *5000000

	// EC策略可以设置的数据块大小的最大值，单位为Byte。默认值4194304，取值范围大于131072
	"dfs.namenode.ec.policies.max.cellsize": int & >=131072 | *4194304

	// 给目录设置EC策略时，如果不指定具体的EC策略，将默认使用该策略。默认值RS-6-3-1024k
	"dfs.namenode.ec.system.default.policy": string & ("RS-3-2-1024k" | "RS-6-3-1024k" | "RS-10-4-1024k" | "RS-LEGACY-6-3-1024k" | "XOR-2-1-1024k") | *"RS-6-3-1024k"

	// 是否对edit日志文件通道进行持久化。默认值false
	"dfs.namenode.edits.noeditlogchannelflush": bool | *false

	// 是否在NameNode启用重试缓存。默认值true，取值范围true或false
	"dfs.namenode.enable.retrycache": bool | *true

	// 所有块提交后文件才关闭，N个块提交且其他块完成后才关闭文件。默认值0，取值范围大于等于0
	"dfs.namenode.file.close.num-committed-allowed": int | *0

	// 每个文件可包含的最大块数，NameNode写操作时使用。默认值1048576，取值范围大于0
	"dfs.namenode.fs-limits.max-blocks-per-file": int & >=1 | *1048576

	// 定义路径的每个组成部分中的最大UTF-8编码字节数。默认值7999，取值范围255~7999
	"dfs.namenode.fs-limits.max-component-length": int & >=255 & <=7999 | *7999

	// 定义目录中包含的最大条目数。默认值1048576，取值范围1~6400000
	"dfs.namenode.fs-limits.max-directory-items": int & >=1 & <=6400000 | *1048576

	// 最小块大小，NameNode创建块时使用。单位：字节，默认值1048576，取值范围大于0
	"dfs.namenode.fs-limits.min-block-size": int & >=1 | *1048576

	// NameNode的RPC服务端用于监听客户端请求的线程数。默认值128，取值范围1~1024
	"dfs.namenode.handler.count": int & >=1 & <=1024 | *128

	// 再次检查DataNode可用性的间隔，单位：毫秒。默认值300000，取值范围1000~86400000
	"dfs.namenode.heartbeat.recheck-interval": int & >=1000 & <=86400000 | *300000

	// Inode属性插件。默认值com.huawei.hadoop.adapter.hdfs.plugin.HWRangerHdfsAuthorizer
	"dfs.namenode.inode.attributes.provider.class": string | *"com.huawei.hadoop.adapter.hdfs.plugin.HWRangerHdfsAuthorizer"

	// NameNode扫描待删除块时扫描的DataNode数量占总DN数量的百分比。默认值0.32，取值范围0~1
	"dfs.namenode.invalidate.work.pct.per.iteration": number | *0.32

	// NameNode的RPC服务端用于处理DataNode的lifeline协议和HA健康检查请求的线程数。默认值16，取值范围1~1024
	"dfs.namenode.lifeline.handler.count": int & >=1 & <=1024 | *16

	// NameNode保存的fsimage文件个数。默认值3，取值范围1~86400
	"dfs.namenode.num.checkpoints.retained": int & >=1 & <=86400 | *3

	// 为NameNode重启所保留的额外事务数。默认值1000000，取值范围大于等于0
	"dfs.namenode.num.extra.edits.retained": int | *1000000

	// 为缓存块映射分配的Java堆比例。默认值"0.25f"
	"dfs.namenode.path.based.cache.block.map.allocation.percent": string | *"0.25f"

	// 初始化Quota的并发线程数。默认值32，取值范围大于0
	"dfs.namenode.quota.init-threads": int & >=1 | *32

	// 块重建的超时参数，单位：秒。默认值900，取值范围大于等于-1
	"dfs.namenode.reconstruction.pending.timeout-sec": int & >=-1 | *900

	// 给新文件选择DataNode时是否考虑DataNode的负载。默认值true，取值范围true或false
	"dfs.namenode.redundancy.considerLoad": bool | *true

	// 当DataNode负载超过平均负载的倍数时，不会选择它存储新文件。默认值4，取值范围1~100
	"dfs.namenode.redundancy.considerLoad.factor": number | *4

	// NameNode发送块复制命令时并行传输的块总量。默认值32，取值范围0~9223372036854775807
	"dfs.namenode.replication.work.multiplier.per.iteration": int & <=9223372036854775807 | *32

	// 重试缓存条目保留时长，单位：毫秒。默认值600000，取值范围大于0
	"dfs.namenode.retrycache.expirytime.millis": int & >=1 | *600000

	// 为重试缓存分配的堆大小比例。默认值"0.03f"
	"dfs.namenode.retrycache.heap.percent": string | *"0.03f"

	// NameNode退出安全模式前的时间，单位：毫秒。默认值15000，取值范围0~3600000
	"dfs.namenode.safemode.extension": int & <=3600000 | *15000

	// NameNode退出安全模式前必须处于alive状态的DataNode数。默认值0，取值范围0~65535
	"dfs.namenode.safemode.min.datanodes": int & <=65535 | *0

	// NameNode的RPC服务端用于监听DataNode请求的线程数。默认值32，取值范围1~1024
	"dfs.namenode.service.handler.count": int & >=1 & <=1024 | *32

	// 将DataNode标记为失效的时间间隔。默认值30000，取值范围大于0
	"dfs.namenode.stale.datanode.interval": int | *30000

	// NameNode启动后，块删除的延迟时间，单位：秒。默认值3600，取值范围0~65535
	"dfs.namenode.startup.delay.block.deletion.sec": int & <=65535 | *3600

	// 当失效DataNode数和总数比值大于该比例时，停止避免写入失效DataNode。默认值0.5f，取值范围0~1f
	"dfs.namenode.write.stale.datanode.ratio": string | *"0.5f"

	// 是否为HDFS启用权限检查。默认值true，取值范围true或false
	"dfs.permissions.ContentSummary.subAccess": bool | *true

	// 是否为HDFS启用权限检查。默认值true，取值范围true或false
	"dfs.permissions.enabled": bool | *true

	// quorum journal edits的队列大小，单位：MB。默认值150，取值范围10~4096
	"dfs.qjournal.queued-edits.limit.mb": int & >=10 & <=4096 | *150

	// 将事务写入大部分quorum journal节点的等待时间，单位：毫秒。默认值20000，取值范围1~3600000
	"dfs.qjournal.write-txns.timeout.ms": int & >=1 & <=3600000 | *20000

	// 最大块副本数。默认值512，取值范围3~1024
	"dfs.replication.max": int & >=3 & <=1024 | *512

	// 启用异构存储。默认值true，取值范围true或false
	"dfs.storage.policy.enabled": bool | *true

	// 流文件缓冲区大小。默认值4096，取值范围大于0
	"dfs.stream-buffer-size": int & >=1 | *4096

	// 是否使用DFSNetworkTopology选择副本放置的DataNode。默认值true，取值范围true或false
	"dfs.use.dfs.network.topology": bool | *true
}
