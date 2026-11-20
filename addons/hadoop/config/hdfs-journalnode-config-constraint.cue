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

#JournalNodeParameter: {
	// 【说明】JournalNode守护进程存储其本地状态的路径。该路径是JournalNode在所在机器上的使用的用来存储edits和其状态一个绝对路径。只可以配置为单个路径。【默认值】${BIGDATA_DATADIR}/journalnode【注意】${BIGDATA_DATADIR}为系统安装时指定的集群数据根目录。请谨慎修改该项。如果配置不当，将造成服务不可用。
	"dfs.journalnode.edits.dir": string | *"/hadoop/dfs/journal"

	// Permissions for the directories on on the local filesystem where the DFS journal node stores the edits. The permissions can either be octal or symbolic.
	"dfs.journalnode.edits.dir.perm": int | *"700"

	// The JournalNode RPC server address and port.
	"dfs.journalnode.rpc-address": string | "0.0.0.0:8485"

	// The address and port the JournalNode HTTP server listens on. If the port is 0 then the server will start on a free port.
	"dfs.journalnode.http-address": string | "0.0.0.0:8480"

	// The address and port the JournalNode HTTPS server listens on. If the port is 0 then the server will start on a free port.
	"dfs.journalnode.https-address": string | "0.0.0.0:8481"

	// The actual address the HTTP server will bind to. If this optional address is set, it overrides only the hostname portion of dfs.journalnode.http-address. This is useful for making the JournalNode HTTP server listen on allinterfaces by setting it to 0.0.0.0.
	"dfs.journalnode.enable.sync": bool | *true

	// 【说明】JournalNode在内存中缓存的edit logs的大小，单位是byte。该缓存用于备/从NameNode通过RPC机制跟踪edit logs，仅当dfs.ha.tail-edits.in-progress时有效。事务的平均大小约为200字节，因此该参数的默认值100MB可以储存大约500000个事务。【默认值】104857600【取值范围】大于1048576
	"dfs.journalnode.edit-cache-size.bytes": int & >=1048576 | *104857600

	// 	Time interval, in milliseconds, between two Journal Node syncs. This configuration takes effect only if the journalnode sync is enabled by setting the configuration parameter dfs.journalnode.enable.sync to true.
	"dfs.journalnode.sync.interval": int & >=1 & <=360000 | *120000

	// 【说明】JVM用于gc的参数。仅当GC_PROFILE设置为custom时该配置才会生效。需确保GC_OPTS参数设置正确，否则进程启动会失败。【默认值】-Xms1G -Xmx2G -XX:NewSize=64M -XX:MaxNewSize=128M -XX:MetaspaceSize=128M -XX:MaxMetaspaceSize=128M -XX:+UseConcMarkSweepGC -XX:+CMSParallelRemarkEnabled -XX:CMSInitiatingOccupancyFraction=65 -XX:PrintGCDateStamps -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=1M -Djdk.tls.ephemeralDHKeySize=3072 -Djdk.tls.rejectClientInitiatedRenegotiation=true -Djava.io.tmpdir=${Bigdata_tmp_dir}
	"GC_OPTS": string | *"-Xms1G -Xmx2G -XX:NewSize=64M -XX:MaxNewSize=128M -XX:MetaspaceSize=128M -XX:MaxMetaspaceSize=128M -XX:+UseConcMarkSweepGC -XX:+CMSParallelRemarkEnabled -XX:CMSInitiatingOccupancyFraction=65 -XX:PrintGCDateStamps -XX:+UseGCLogFileRotation -XX:NumberOfGCLogFiles=10 -XX:GCLogFileSize=1M -Djdk.tls.ephemeralDHKeySize=3072 -Djdk.tls.rejectClientInitiatedRenegotiation=true -Djava.io.tmpdir=${Bigdata_tmp_dir}"

	// 【说明】设置可用于gc的内存大小等级。high表示4G，medium表示2G，low表示256M，custom表示根据实际数据量大小在GC_OPTS中设置内存大小。【默认值】custom【取值范围】high，medium，low，custom
	"GC_PROFILE": string & ("high" | "medium" | "low" | "custom") | *"custom"

	// 【说明】web服务器允许的最大请求数。【默认值】2000【取值范围】1~1000000
	"hadoop.http.server.MaxRequests": int & >=1 & <=1000000 | *2000

	// 【说明】运行日志文件的最大个数。【默认值】100【取值范围】1~999
	"hadoop.log.maxbackupindex": int & >=1 & <=999 | *100

	// 【说明】单个运行日志文件的最大大小。【默认值】100 MB
	"hadoop.log.maxfilesize": string | *"100MB"

	// 【说明】审计日志级别。【默认值】INFO【取值范围】TRACE、DEBUG、INFO、WARN、ERROR、OFF
	"hdfs.audit.log.level": string & ("TRACE" | "DEBUG" | "INFO" | "WARN" | "ERROR" | "OFF") | *"INFO"

	// 【说明】审计日志文件的最大个数。【默认值】100【取值范围】1~999
	"hdfs.audit.log.maxbackupindex": int & >=1 & <=999 | *100

	// 【说明】单个审计日志文件的最大大小。【默认值】100MB
	"hdfs.audit.log.maxfilesize": string | *"100MB"

	// 【说明】日志级别。【默认值】INFO【取值范围】DEBUG、INFO、WARN、ERROR、FATAL
	"hdfs.log.level": string & ("DEBUG" | "INFO" | "WARN" | "ERROR" | "FATAL") | *"INFO"

	// 【说明】安全审计日志级别。【默认值】WARN【取值范围】INFO、WARN、ERROR、OFF
	"hdfs.security.log.level": string & ("INFO" | "WARN" | "ERROR" | "OFF") | *"WARN"

	// 【说明】用于指定写入Sequence文件时的缓冲数据的长度，也用于指定读写文件时的缓冲数据的长度，单位为Byte。【默认值】131072【取值范围】大于或等于4096【注意】该大小需要设置为硬件页面大小（Intel x86硬件上，页面大小为4096）的整数倍。
	"io.file.buffer.size": int & >=1024 | *131072
}
