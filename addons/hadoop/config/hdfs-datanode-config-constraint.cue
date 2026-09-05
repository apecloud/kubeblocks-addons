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

#DataNodeParameter: {
	// The datanode server address and port for data transfer.
	"dfs.datanode.address": string | "0.0.0.0:9866"

	// The datanode http server address and port.
	"dfs.datanode.http.address": string | "0.0.0.0:9864"

	// The datanode ipc server address and port.
	"dfs.datanode.ipc.address	": string | "0.0.0.0:9867"

	// DataNode配置中用于指定允许进行短路读操作的用户的密钥。
	"dfs.block.local-path-access.user"?: string

	// 若设置为正整数，表示从DataNode向NameNode上报新增块的等待时间，单位：ms。默认值0，取值范围0~86400000
	"dfs.blockreport.incremental.intervalMsec": int & <=86400000 | *0

	// 首次块上报的延时时间，单位：秒。默认值0，取值范围0~1500
	"dfs.blockreport.initialDelay": int & <=1500 | *0

	// 块上报间隔时间，单位：毫秒。默认值21600000，取值范围100~86400000
	"dfs.blockreport.intervalMsec": int & >=100 & <=86400000 | *21600000

	// DataNode上的块数低于此阈值时将单个消息发送块报告，超过时分开发送。默认值1000000，取值范围0~2000000
	"dfs.blockreport.split.threshold": int & <=2000000 | *1000000

	// 每个校验和的字节数，不能大于dfs.stream-buffer-size且必须能被dfs.blocksize整除。默认值512，取值范围大于0
	"dfs.bytes-per-checksum": int & >=1 | *512

	// 控制新块分配到拥有更多可用磁盘空间的卷的比例，适用于AvailableSpaceVolumeChoosingPolicy。默认值0.75，取值范围0~1
	"dfs.datanode.available-space-volume-choosing-policy.balanced-space-preference-fraction": number | *0.75

	// 控制DataNode卷的负载均衡范围，适用于AvailableSpaceVolumeChoosingPolicy。默认值10737418240，取值范围大于0
	"dfs.datanode.available-space-volume-choosing-policy.balanced-space-threshold": int & >=1 | *10737418240

	// DataNode可用于负载均衡的最大带宽量（每秒的字节数）。默认值20971520，取值范围1048576~1073741824
	"dfs.datanode.balance.bandwidthPerSec": int & >=1048576 & <=1073741824 | *20971520

	// 允许在DataNode上进行负载均衡的最大线程数。默认值32，取值范围5~1000
	"dfs.datanode.balance.max.concurrent.moves": int & >=5 & <=1000 | *32

	// 是否禁止移动写入指定DataNode上的数据块。默认值false
	"dfs.datanode.block-pinning.enabled": bool | *false

	// DataNode升级时创建前一版本到当前版本硬链接的线程数。默认值24，取值范围大于1
	"dfs.datanode.block.id.layout.upgrade.threads": int & >=1 | *24

	// DataNode在本地文件系统中存储块的位置。默认值%{@auto.detect.datapart.dn}
	"dfs.datanode.data.dir": string | *"%{@auto.detect.datapart.dn}"

	// dfs.datanode.data.dir的权限。默认值700
	"dfs.datanode.data.dir.perm": string | *700

	// DataNode扫描数据目录在磁盘上的块和内存中的块之间的区别的间隔时间，单位：秒。默认值21600，取值范围1~258000
	"dfs.datanode.directoryscan.interval": int & >=1 & <=258000 | *21600

	// 并行扫描DataNode目录并生成报告的线程数。默认值1，取值范围1~1024
	"dfs.datanode.directoryscan.threads": int & >=1 & <=1024 | *1

	// DataNode应该上报它IP地址的网络接口名称。默认值"default"
	"dfs.datanode.dns.interface": string | *"default"

	// DataNode在和NameNode交流时应该用的DNS服务地址主机名或IP地址。默认值"default"
	"dfs.datanode.dns.nameserver": string | *"default"

	// 是否在读取数据后自动清除缓存中的数据。默认值false
	"dfs.datanode.drop.cache.behind.reads": bool | *false

	// 是否在写入磁盘后自动清除缓存中的数据。默认值false
	"dfs.datanode.drop.cache.behind.writes": bool | *false

	// 每个磁盘的保留空间，单位：字节。默认值0，取值范围大于等于0
	"dfs.datanode.du.reserved": int | *0

	// DataNode上EC数据块的读取缓存大小，单位：字节。默认值131072，取值范围大于1024
	"dfs.datanode.ec.reconstruction.stripedread.buffer.size": int & >=1024 | *131072

	// DataNode上EC数据块的读取超时时间，单位：毫秒。默认值15000，取值范围大于2000
	"dfs.datanode.ec.reconstruction.stripedread.timeout.millis": int & >=2000 | *15000

	// DataNode进行EC数据块恢复的线程数。默认值32，取值范围1~1024
	"dfs.datanode.ec.reconstruction.threads": int & >=1 & <=1024 | *32

	// EC数据块恢复线程数的比重。默认值0.5，取值范围0~1
	"dfs.datanode.ec.reconstruction.xmits.weight": number | *0.5

	// DataNode停止提供服务前允许失败的卷数。默认值-1，取值范围-1~32768
	"dfs.datanode.failed.volumes.tolerated": int & >=-1 & <=32768 | *-1

	// DataNode写操作时选择副本的存放位置时考虑每个卷的可用磁盘空间。默认值AvailableSpaceVolumeChoosingPolicy
	"dfs.datanode.fsdataset.volume.choosing.policy": string & ("org.apache.hadoop.hdfs.server.datanode.fsdataset.RoundRobinVolumeChoosingPolicy" | "org.apache.hadoop.hdfs.server.datanode.fsdataset.AvailableSpaceVolumeChoosingPolicy") | *"org.apache.hadoop.hdfs.server.datanode.fsdataset.AvailableSpaceVolumeChoosingPolicy"

	// 每个卷用于缓存新数据的最大线程数。默认值4，取值范围大于0
	"dfs.datanode.fsdatasetcache.max.threads.per.volume": int & >=1 | *4

	// DataNode的服务线程数。默认值32，取值范围1~1024
	"dfs.datanode.handler.count": int & >=1 & <=1024 | *32

	// DataNode的内部web代理端口。默认值50175，取值范围1024~65535
	"dfs.datanode.http.internal-proxy.port": int & >=1024 & <=65535 | *50175

	// 从DataNode向NameNode发送Lifeline协议消息的间隔周期，单位：秒
	"dfs.datanode.lifeline.interval.seconds"?: int

	// DataNode用于缓存块副本的内存大小，单位：字节。默认值0，取值范围0~1800000000000
	"dfs.datanode.max.locked.memory": int & <=1800000000000 | *0

	// DataNode间传输数据的线程的最大数。默认值8192，取值范围1~32768
	"dfs.datanode.max.transfer.threads": int & >=1 & <=32768 | *8192

	// 要激活的DataNode插件清单
	"dfs.datanode.plugins"?: string

	// DataNode尝试预先读取的字节数。默认值4194304，取值范围大于等于0
	"dfs.datanode.readahead.bytes": int | *4194304

	// DataNode是否指示操作系统在写数据后立即写入磁盘。默认值true，取值范围true或false
	"dfs.datanode.sync.behind.writes": bool | *true

	// DataNode向NameNode发送心跳的时间间隔，单位：秒。默认值10，取值范围3~180
	"dfs.heartbeat.interval": int & >=3 & <=180 | *10

	// DataNode启用拥塞信令能力。默认值false，取值范围true或false
	"dfs.pipeline.ecn": bool | *false

	// 流文件缓冲区的大小。默认值4096，取值范围大于0
	"dfs.stream-buffer-size": int & >=1 | *4096

	// 【说明】是否禁止移动写入指定DataNode上的数据块。该参数值设置为true，在进行Balancer或Mover时，使用colocation写入的文件将不会被移动。【默认值】false
	"dfs.datanode.block-pinning.enabled": bool | *false

	// 【说明】设置从DataNode向NameNode发送DataNode Lifeline协议消息的间隔周期。单位：秒。该参数值必须大于dfs.heartbeat.interval的值。如果不定义该参数，则默认计算值是dfs.heartbeat.interval值的3倍。
	"dfs.datanode.lifeline.interval.seconds"?: int

	// 【说明】是否允许备/从NameNode跟踪in-progress状态的edit logs。当客户希望备/从NameNode节点拥有更多较新的数据时，可以设置该参数为true。当QuorumJournalManager共享edit logs时，该参数允许通过RPC机制获取edit logs，而不是文件流，这使得数据传输更快。当使用从NameNode处理读操作时，该参数必须设置为true。【默认值】true
	"dfs.ha.tail-edits.in-progress": bool | *true

	// 【说明】DataNode向NameNode发送心跳的时间间隔，单位为秒。【默认值】10【取值范围】3~180
	"dfs.heartbeat.interval": int & >=3 & <=180 | *10
}