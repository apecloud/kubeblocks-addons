#PDParameter: {
	// The timeout of the PD Leader Key lease. After the timeout, the system re-elects a Leader. Unit: second
	"lease": string | *"3"

	// The storage size of the meta-information database, which is 8GiB by default
	"quota-backend-bytes": string | *"8589934592"

	// The automatic compaction modes of the meta-information database. Available options: `periodic` (by cycle) and `revision` (by version number).
	"auto-compaction-mod": string | *"periodic"

	// The time interval for automatic compaction of the meta-information database when `auto-compaction-retention` is `periodic`. When the compaction mode is set to `revision`, this parameter indicates the version number for the automatic compaction.
	"auto-compaction-retention": string | *"1h"

	// Determines whether to force PD to start as a new cluster and modify the number of Raft members to `1`
	"force-new-cluster": bool | *false

	// The interval at which PD updates the physical time of TSO. In a default update interval of TSO physical time, PD provides at most 262144 TSOs. To get more TSOs, you can reduce the value of this configuration item. The minimum value is `1ms`. Decreasing this configuration item might increase the CPU usage of PD. According to the test, compared with the interval of `50ms`, the [CPU usage](https://man7.org/linux/man-pages/man1/top.1.html) of PD will increase by about 10% when the interval is `1ms`.
	"tso-update-physical-interval": string & >=0 | *"50ms"

	// The memory limit ratio for a PD instance. The value `0` means no memory limit.
	"pd-server.server-memory-limit": float & >=0 & <=0.99 | *0

	// The threshold ratio at which PD tries to trigger GC. When the memory usage of PD reaches the value of `server-memory-limit` * the value of `server-memory-limit-gc-trigger`, PD triggers a Golang GC. Only one GC is triggered in one minute.
	"pd-server.server-memory-limit-gc-trigger": float & >=0.5 & <=0.99 | *0.7

	// Controls whether to enable the GOGC Tuner.
	"pd-server.enable-gogc-tuner": bool | *false

	// The maximum memory threshold ratio for tuning GOGC. When the memory exceeds this threshold, i.e. the value of `server-memory-limit` * the value of `gc-tuner-threshold`, GOGC Tuner stops working.
	"pd-server.gc-tuner-threshold": float & >=0 & <=0.90 | *0.6

	// PD rounds the lowest digits of the flow number, which reduces the update of statistics caused by the changes of the Region flow information. This configuration item is used to specify the number of lowest digits to round for the Region flow information. For example, the flow `100512` will be rounded to `101000` because the default value is `3`. This configuration replaces `trace-region-flow`.
	"pd-server.flow-round-by-digit": string | *"3"

	// Determines the interval at which the minimum resolved timestamp is persistent to the PD. If this value is set to `0`, it means that the persistence is disabled. Unit: second
	"pd-server.min-resolved-ts-persistence-interval": float & >=0 | *1

	// The path of the CA file
	"security.cacert-path": string

	// The path of the Privacy Enhanced Mail (PEM) file that contains the X509 certificate
	"security.cert-path": string

	// The path of the PEM file that contains the X509 key
	"security.key-path": string

	// Controls whether to enable log redaction in the PD log. When you set the configuration value to `true`, user data is redacted in the PD log.
	"security.redact-info-log": bool | *false

	// Specifies the level of the output log. Optional value: `"debug"`, `"info"`, `"warn"`, `"error"`, `"fatal"`
	"log.level": string | *"info"

	// The log format. Optional value: `"text"`, `"json"`
	"log.format": string | *"text"

	// Whether to disable the automatically generated timestamp in the log
	"log.disable-timestamp": bool | *false

	// The maximum size of a single log file. When this value is exceeded, the system automatically splits the log into several files. Unit: MiB
	"log.file.max-size": float & >=1 | *300

	// The maximum number of days in which a log is kept. If the configuration item is not set, or the value of it is set to the default value 0, PD does not clean log files.
	"log.file.max-days": string | *"0"

	// The maximum number of log files to keep. If the configuration item is not set, or the value of it is set to the default value 0, PD keeps all log files.
	"log.file.max-backups": string | *"0"

	// The interval at which monitoring metric data is pushed to Prometheus
	"metric.interval": string | *"15s"

	// Controls the size limit of `Region Merge`. When the Region size is greater than the specified value, PD does not merge the Region with the adjacent Regions. Unit: MiB
	"schedule.max-merge-region-size": string | *"20"

	// Specifies the upper limit of the `Region Merge` key. When the Region key is greater than the specified value, the PD does not merge the Region with its adjacent Regions.
	"schedule.max-merge-region-keys": string | *"200000"

	// Controls the running frequency at which `replicaChecker` checks the health state of a Region. The smaller this value is, the faster `replicaChecker` runs. Normally, you do not need to adjust this parameter.
	"schedule.patrol-region-interval": string | *"10ms"

	// Controls the time interval between the `split` and `merge` operations on the same Region. That means a newly split Region will not be merged for a while.
	"schedule.split-merge-interval": string | *"1h"

	// Controls the maximum number of snapshots that a single store receives or sends at the same time. PD schedulers depend on this configuration to prevent the resources used for normal traffic from being preempted.
	"schedule.max-snapshot-count": string | *"Default value value: `64"

	// Controls the maximum number of pending peers in a single store. PD schedulers depend on this configuration to prevent too many Regions with outdated logs from being generated on some nodes.
	"schedule.max-pending-peer-count": string | *"64"

	// The downtime after which PD judges that the disconnected store cannot be recovered. When PD fails to receive the heartbeat from a store after the specified period of time, it adds replicas at other nodes.
	"schedule.max-store-down-time": string | *"30m"

	// Controls the maximum waiting time for the store to go online. During the online stage of a store, PD can query the online progress of the store. When the specified time is exceeded, PD assumes that the store has been online and cannot query the online progress of the store again. But this does not prevent Regions from transferring to the new online store. In most scenarios, you do not need to adjust this parameter.
	"schedule.max-store-preparing-time": string | *"48h"

	// The number of Leader scheduling tasks performed at the same time
	"schedule.leader-schedule-limit": string | *"4"

	// The number of Region scheduling tasks performed at the same time
	"schedule.region-schedule-limit": string | *"2048"

	// Controls whether to enable the diagnostic feature. When it is enabled, PD records the state during scheduling to help diagnose. If enabled, it might slightly affect the scheduling speed and consume more memory when there are many stores.
	"schedule.enable-diagnostic": bool | *true

	// Controls the hot Region scheduling tasks that are running at the same time. It is independent of the Region scheduling.
	"schedule.hot-region-schedule-limit": string | *"4"

	// The threshold used to set the number of minutes required to identify a hot Region. PD can participate in the hotspot scheduling only after the Region is in the hotspot state for more than this number of minutes.
	"schedule.hot-region-cache-hits-threshold": string | *"3"

	// The number of Replica scheduling tasks performed at the same time
	"schedule.replica-schedule-limit": string | *"64"

	// The number of the `Region Merge` scheduling tasks performed at the same time. Set this parameter to `0` to disable `Region Merge`.
	"schedule.merge-schedule-limit": string | *"8"

	// The threshold ratio below which the capacity of the store is sufficient. If the space occupancy ratio of the store is smaller than this threshold value, PD ignores the remaining space of the store when performing scheduling, and balances load mainly based on the Region size. This configuration takes effect only when `region-score-formula-version` is set to `v1`.
	"schedule.high-space-ratio": string & >=0 & <=0 | *"0.7"

	// The threshold ratio above which the capacity of the store is insufficient. If the space occupancy ratio of a store exceeds this threshold value, PD avoids migrating data to this store as much as possible. Meanwhile, to avoid the disk space of the corresponding store being exhausted, PD performs scheduling mainly based on the remaining space of the store.
	"schedule.low-space-ratio": string & >=0 & <=0 | *"0.8"

	// Controls the `balance` buffer size
	"schedule.tolerant-size-ratio": float & >=0 | *0

	// Determines whether to enable the merging of cross-table Regions
	"schedule.enable-cross-table-merge": bool | *true

	// Controls the version of the Region score formula. Optional values: `v1` and `v2`. Compared to v1, the changes in v2 are smoother, and the scheduling jitter caused by space reclaim is improved.
	"schedule.region-score-formula-version": string | *"v2"

	// Controls the version of the store limit formula. Value options:`v1`: In v1 mode, you can manually modify the `store limit` to limit the scheduling speed of a single TiKV.`v2`: (experimental feature) In v2 mode, you do not need to manually set the `store limit` value, as PD dynamically adjusts it based on the capability of TiKV snapshots. For more details, refer to [Principles of store limit v2](/configure-store-limit.md#principles-of-store-limit-v2).
	"schedule.store-limit-version": string | *"v1"

	// Controls whether to use Joint Consensus for replica scheduling. If this configuration is disabled, PD schedules one replica at a time.
	"schedule.enable-joint-consensus": bool | *true

	// The time interval at which PD stores hot Region information.
	"schedule.hot-regions-write-interval": string | *"10m"

	// Specifies how many days the hot Region information is retained.
	"schedule.hot-regions-reserved-days": string | *"7"

	// The number of replicas, that is, the sum of the number of leaders and followers. The default value `3` means 1 leader and 2 followers. When this configuration is modified dynamically, PD will schedule Regions in the background so that the number of replicas matches this configuration.
	"replication.max-replicas": string | *"3"

	// The topology information of a TiKV cluster. [Cluster topology configuration](/schedule-replicas-by-topology-labels.md)
	"replication.location-labels": [...string] | *[]

	// The minimum topological isolation level of a TiKV cluster. [Cluster topology configuration](/schedule-replicas-by-topology-labels.md)
	"replication.isolation-level": string

	// Enables the strict check for whether the TiKV label matches PD's `location-labels`.
	"replication.strictly-match-label": bool | *false

	// Enables `placement-rules`. See [Placement Rules](/configure-placement-rules.md).
	"replication.enable-placement-rules": bool | *true

	// The path of the root CA certificate file. You can configure this path when you connect to TiDB's SQL services using TLS.
	"dashboard.tidb-cacert-path": string

	// The path of the SSL certificate file. You can configure this path when you connect to TiDB's SQL services using TLS.
	"dashboard.tidb-cert-path": string

	// The path of the SSL private key file. You can configure this path when you connect to TiDB's SQL services using TLS.
	"dashboard.tidb-key-path": string

	// When TiDB Dashboard is accessed behind a reverse proxy, this item sets the public URL path prefix for all web resources. Do **not** modify this configuration item when TiDB Dashboard is accessed not behind a reverse proxy; otherwise, access issues might occur. See [Use TiDB Dashboard behind a Reverse Proxy](/dashboard/dashboard-ops-reverse-proxy.md) for details.
	"dashboard.public-path-prefix": string | *"/dashboard"

	// Determines whether to enable the telemetry collection feature in TiDB Dashboard. See [Telemetry](/telemetry.md) for details.
	"dashboard.enable-telemetry": bool | *false

	// Time to wait to trigger the degradation mode. Degradation mode means that when the Local Token Bucket (LTB) and Global Token Bucket (GTB) are lost, the LTB falls back to the default resource group configuration and no longer has a GTB authorization token, thus ensuring that the service is not affected in the event of network isolation or anomalies. The degradation mode is disabled by default.
	"controller.degraded-mode-wait-duration": string | *"0s"

	// Basis factor for conversion from a read request to RU
	"controller.request-unit": string | *"0.125"

	...
}

configuration: #PDParameter & {}
