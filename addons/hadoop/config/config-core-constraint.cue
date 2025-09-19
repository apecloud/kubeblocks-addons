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

#HadoopCoreParameter: {
	// 说明: Hadoop tmp 数据目录。
	"hadoop.tmp.dir": string | *"/tmp/hadoop"

    "fs.default.name": string | *"hdfs://{{ .CLUSTER_NAME }}"

	//  说明:默认的文件系统名。
	"fs.defaultFS": string | *"hdfs://{{ .CLUSTER_NAME }}"

	// A comma separated list of class names. Each class in the list must extend org.apache.hadoop.http.FilterInitializer. The corresponding Filter will be initialized. Then, the Filter will be applied to all user facing jsp and servlet web pages. The ordering of the list defines the ordering of the filters
	"hadoop.http.filter.initializers": string | "org.apache.hadoop.http.lib.StaticUserWebFilter"

	// NN/JN/DN Server connection timeout in milliseconds.
	"hadoop.http.idle_timeout.ms": int | 60000

	// 	The name of the Network Interface from which the service should determine its host name for Kerberos login. e.g. eth2. In a multi-homed environment, the setting can be used to affect the _HOST substitution in the service Kerberos principal. If this configuration value is not set, the service will use its default hostname as returned by InetAddress.getLocalHost().getCanonicalHostName(). Most clusters will not require this setting.
	"hadoop.security.dns.interface"?: string

	// The host name or IP address of the name server (DNS) which a service Node should use to determine its own host name for Kerberos Login. Requires hadoop.security.dns.interface. Most clusters will not require this setting.
	"hadoop.security.dns.nameserver"?: string

	// The resolver implementation used to resolve FQDN for Kerberos
	"hadoop.security.resolver.impl": string | *"org.apache.hadoop.net.DNSDomainNameResolver"

	// 	Time name lookups (via SecurityUtil) and log them if they exceed the configured threshold.
	"hadoop.security.dns.log-slow-lookups.enabled": bool & (true | false) | *false

	// If slow lookup logging is enabled, this threshold is used to decide if a lookup is considered slow enough to be logged.
	"hadoop.security.dns.log-slow-lookups.threshold.ms": int | *1000

	// This is the config controlling the validity of the entries in the cache containing the user->group mapping. When this duration has expired, then the implementation of the group mapping provider is invoked to get the groups of the user and then cached back.
	"hadoop.security.groups.cache.secs": int | *300

	// Expiration time for entries in the the negative user-to-group mapping caching, in seconds. This is useful when invalid users are retrying frequently. It is suggested to set a small value for this expiration, since a transient error in group lookup could temporarily lock out a legitimate user. Set this to zero or negative value to disable negative user-to-group caching.
	"hadoop.security.groups.negative-cache.secs": int | *30

	// If looking up a single user to group takes longer than this amount of milliseconds, we will log a warning message.
	"hadoop.security.groups.cache.warn.after.ms": int | *5000

	// Whether to reload expired user->group mappings using a background thread pool. If set to true, a pool of hadoop.security.groups.cache.background.reload.threads is created to update the cache in the background.
	"hadoop.security.groups.cache.background.reload": bool & (true | false) | *false

	// 3	Only relevant if hadoop.security.groups.cache.background.reload is true. Controls the number of concurrent background user->group cache entry refreshes. Pending refresh requests beyond this value are queued and processed when a thread is free.
	"hadoop.security.groups.cache.background.reload.threads": int | *3

	//  说明:与内置的sshfence相关的SSH连接超时时间。单位：毫秒。 默认值:10000 取值范围:1~3600000
	"dfs.ha.fencing.ssh.connect-timeout": int & >=1 & <=3600000 | *10000

	//  说明:创建文件及目录时使用的umask。可以是八进制数或符号型的。比如："022"（这是八进制数，对应的符号型数值是"u=rwx,g=r-x,o=r-x"）或"u=rwx,g=rwx,o="（这是符号型数值，对应的八进制数是007）。 默认值:022
	"fs.permissions.umask-mode": string | *"022"

	//  说明:访问S3A文件系统使用的秘钥ID,若不设置默认为空。
	"fs.s3a.access.key"?: string

	//  说明:是否启动SSL连接和S3服务。 默认值:false 取值范围:true, false
	"fs.s3a.connection.ssl.enabled": bool | *false

	//  说明:访问S3A文件系统使用的秘钥,若不设置默认为空。
	"fs.s3a.secret.key"?: string

	//  说明:访问S3时使用的签名算法。默认使用旧版本S3SignerType签名算法。如果不指定此参数，则使用默认的签名算法但可能存在兼容性问题。 默认值:S3SignerType 取值范围:S3SignerType或不指定。
	"fs.s3a.signing-algorithm": string & ("S3SignerType") | *"S3SignerType"

	//  说明:zkfc对namenode健康状态检查的超时时间。单位：毫秒。增大该参数值，可以防止出现双Active NameNode，降低客户端应用运行异常的概率。 默认值:180000 取值范围:30000~3600000
	"ha.health-monitor.rpc-timeout.ms": int & >=30000 & <=3600000 | *180000

	//  说明:Zkfc连接到ZooKeeper时使用的会话超时时间。单位：毫秒。如果将该参数设置为较小的值，那可以更快地监测到服务器瘫痪故障，但如果出现瞬变错误或网络中断则有强制触发切换的风险。 默认值:90000 取值范围:1~3600000
	"ha.zookeeper.session-timeout.ms": int & >=1 & <=3600000 | *90000

	//  说明:存储鉴权令牌的HTTP cookie所使用的域。为了在所有Hadoop节点web控制台间正确地进行鉴权，该域必须配置正确。重要：使用IP地址时，浏览器会忽略带有域设置的cookies。为保证该设置的正常使用，集群中的所有节点都必须配置为使用上面的hostname.domain名来生成URL。
	"hadoop.http.authentication.cookie.domain"?: string

	//  说明:通过静态网页可以呈现内容的用户名。 默认值:hdfs
	"hadoop.http.staticuser.user": string | *"hdfs"

	//  说明:设置Hadoop中各模块的RPC通道是否加密。对RPC的加密方式，有如下三种取值：    authentication：只进行认证，不加密；    integrity：进行认证和一致性校验；    privacy：进行认证、一致性校验、加密。 默认值:S的上层服务，且不支持滚动重启。重启过程中会造成业务中断，请谨慎修改。
	"hadoop.rpc.protection": string & ("authentication" | "privacy" | "integrity") | *"privacy"

	//  说明: 选择 Hadoop 使用的身份验证机制.  默认值:kerberos 取值范围:kerberos
	"hadoop.security.authentication": string & ("kerberos") | *"kerberos"

	//  说明: 启用授权.  默认值:true 取值范围:true, false   注意:修改该配置为false后会停用Kerberos，存在安全风险，请谨慎操作。
	"hadoop.security.authorization": bool | *true

	//  说明:ACL中用于用户和组之间的映射（为指定用户获取组）的类。该类使用bash -c groups命令临时接入到Linux/Unix环境为用户获取组清单。org.apache.hadoop.security.JniBasedUnixGroupsMappingWithFallback决定JNI（Ja用，将使用ShellBasedUnixGroupsMapping。 默认值:org.apache.hadoop.security.JniBasedUnixGroupsMappingWithFallback 取值范围:org.apache.hadoop.security.ShellBasedUnixGroupsMapping 或 org.apache.hadoop.securityroupsMappingWithFallback
	"hadoop.security.group.mapping": string & ("org.apache.hadoop.security.ShellBasedUnixGroupsMapping" | "org.apache.hadoop.security.JniBasedUnixGroupsMappingWithFallback") | *"org.apache.hadoop.security.JniBasedUnixGroupsMappingWithFallback"

	//  说明:由ShellBasedUnixGroupsMapping类使用，此属性控制要等待运行获取组的shell命令的时间。配置值可采用时间后缀s/m/h表示，分别表示秒，分钟和小时。 如果运行命令的时间比配置的值长，则该命令将中止并返回没有找到任何组的结果。配置为“0s”表示无限等待 (即等待命令自行退出)。 默认值:60s
	"hadoop.security.groups.shell.command.timeout": string | *"60s"

	//  说明:通过HTTP或HTTPS访问HDFS的JMX, METRICS, CONF, STACKS等信息时，是否需要管理员权限。 默认值:true 取值范围:true, false   注意:修改该配置为false后，降低了安全等级，请谨慎操作。
	"hadoop.security.instrumentation.requires.admin": bool | *true

	//  说明:通过delegation token认证时，是否使用ip地址作为tokens的service key。 默认值:true 取值范围:true, false
	"hadoop.security.token.service.use_ip": bool | *true

	//  说明:SSL支持的协议列表（用逗号分隔）。 默认值:TLSv1.2   注意:使用低版本协议，存在安全风险，请谨慎操作。
	"hadoop.ssl.enabled.protocols": string | *"TLSv1.2"

	//  说明:定义压缩编码解码库中的所有压缩编码。可用于压缩/解压缩的压缩编码类的列表，列表中各项以逗号分隔。除了带有该属性的类（优先级高）之外，类路径上的压缩编码类也都是通过Java ServiceLoader发现的。 默认值:oache.hadoop.io.compress.DeflateCodec,org.apache.hadoop.io.compress.Lz4Codec,org.apache.hadoop.io.compress.SnappyCodec,org.apache.hadoop.io.compress.GzipCodec.
	"io.compression.codecs": string | *"org.apache.hadoop.io.compress.BZip2Codec,org.apache.hadoop.io.compress.DefaultCodec,org.apache.hadoop.io.compress.DeflateCodec,org.apache.hadoop.io.compress.Lz4Codec,org.apache.hadoop.io.compress.SnappyCodec,org.apache.hadoop.io.compress.GzipCodec,org.apache.hadoop.io.compress.ZStandardCodec"

	//  说明:用于指定写入Sequence文件时的缓冲数据的长度，也用于指定读写文件时的缓冲数据的长度，单位为Byte。 默认值:131072 取值范围:大于或等于4096 注意:该大小需要设置为硬件页面大小（Intel x86硬件上，页面大小为4096）的整数倍。
	"io.file.buffer.size": int & >=1024 | *131072

	//  说明:客户端与服务端建立Socket连接超时时，客户端的重试次数。 默认值:45 取值范围:1~256
	"ipc.client.connect.max.retries.on.timeouts": int & >=1 & <=256 | *45

	//  说明:客户端与服务端建立socket连接的超时时间。单位：毫秒。 默认值:20000 取值范围:1~3600000
	"ipc.client.connect.timeout": int & >=1 & <=3600000 | *20000

	//  说明:当客户端连接安全服务后，转向连接非安全服务时，服务端指引客户端进行非安全认证。该配置项控制客户端是否进行非安全认证。当设置为默认false时，禁止客户端回落到非安全认证，并断开连接。 默认值:true
	"ipc.client.fallback-to-simple-auth-allowed": bool | *true

	//  说明:进行空闲情况检查的连接的个数阈值。 默认值:4000 取值范围:大于 0
	"ipc.client.idlethreshold": int & >=1 | *4000

	//  说明:一次操作中可断连的最大客户端数。 默认值:10 取值范围:大于 0
	"ipc.client.kill.max": int & >=1 | *10

	//  说明:表示是否要启用在RPC客户端上ping服务器。 默认值:true 取值范围:true 或 false
	"ipc.client.ping": bool | *true

	//  说明:客户端ipc超时时间。单位：毫秒。 默认值:300000 取值范围:1~3600000
	"ipc.client.rpc-timeout.ms": int & >=1 & <=3600000 | *300000

	//  说明:DataNode连接NameNode时可用的最大IPC数据大小。 默认值:268435456 取值范围:67108864~4294967296
	"ipc.maximum.data.length": int & >=67108864 & <=4294967296 | *268435456

	//  说明:从RPC客户端向服务器发送ping包的间隔。单位：毫秒。 默认值:60000 取值范围:1~3600000
	"ipc.ping.interval": int & >=1 & <=3600000 | *60000

	//  说明:表示服务器接受客户端连接的监听队列的长度。 默认值:128 取值范围:1~8192
	"ipc.server.listen.queue.size": int & >=1 & <=8192 | *128

	//  说明:此设置可用于解决各种服务的性能问题。如果该值设置为true，处理时间多于99%的RPC请求的请求视为慢请求，记录于日志中并增加RpcSlowCalls的值。 默认值:false 取值范围:true 或 false
	"ipc.server.log.slow.rpc": bool | *false
}
