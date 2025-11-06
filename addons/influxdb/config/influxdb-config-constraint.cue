#InfluxdbParameter: {
	// Override the default InfluxDB user interface (UI) assets by serving assets from the specified directory. Typically, InfluxData internal use only.
	"assets-path"?: string

	// Path to the BoltDB database. BoltDB is a key value store written in Go. InfluxDB uses BoltDB to store data including organization and user information, UI data, REST resources, and other key value data.
	"bolt-path"?: string

	// Add a /debug/flush endpoint to the InfluxDB HTTP API to clear stores. InfluxData uses this endpoint in end-to-end testing.
	"e2e-testing"?: bool & false | true | *false

	// Path to persistent storage engine files where InfluxDB stores all Time-Structure Merge Tree (TSM) data on disk.
	"engine-path"?: string

	// Include option to show detailed logs for Flux queries
	"flux-log-enabled"?: bool & false | true | *false

	// Enable additional security features in InfluxDB
	"hardening-enabled"?: bool & false | true | *false

	// Bind address for the InfluxDB HTTP API. Customize the URL and port for the InfluxDB API and UI.
	"http-bind-address"?: string | *":8086"

	// Maximum duration the server should keep established connections alive while waiting for new requests. Set to 0 for no timeout.
	"http-idle-timeout"?: string | *"180s"

	// Maximum duration the server should try to read HTTP headers for new requests. Set to 0 for no timeout.
	"http-read-header-timeout"?: string | *"10s"

	// Maximum duration the server should try to read the entirety of new requests. Set to 0 for no timeout.
	"http-read-timeout"?: string | *"0s"

	// Maximum duration to wait before timing out writes of the response. It doesn’t let Handlers decide the duration on a per-request basis.
	"http-write-timeout"?: string | *"0s"

	// Maximum number of group by time buckets a SELECT statement can create. 0 allows an unlimited number of buckets.
	"influxql-max-select-buckets"?: int & >= 0 | *0

	// Maximum number of points a SELECT statement can process. 0 allows an unlimited number of points. InfluxDB checks the point count every second (so queries exceeding the maximum aren’t immediately aborted).
	"influxql-max-select-point"?: int & >= 0 | *0

	// Maximum number of series a SELECT statement can return. 0 allows an unlimited number of series.
	"influxql-max-select-series"?: int & >= 0 | *0

	// Identifies edge nodes during replication, and prevents collisions if two edge nodes write the same measurement,tagset.
	"instance-id"?: string

	// Log output level. InfluxDB outputs log entries with severity levels greater than or equal to the level specified.
	"log-level"?: "error" | "info" | "debug" | *"info"

	// Disable the HTTP /metrics endpoint which exposes internal InfluxDB metrics.
	"metrics-disabled"?: bool & false | true | *false

	// Disable the task scheduler. If problematic tasks prevent InfluxDB from starting, use this option to start InfluxDB without scheduling or executing tasks.
	"no-tasks"?: bool & false | true | *false

	// Disable the /debug/pprof HTTP endpoint. This endpoint provides runtime profiling data and can be helpful when debugging.
	"pprof-disabled"?: bool & false | true | *false

	// Number of queries allowed to execute concurrently. Setting to 0 allows an unlimited number of concurrent queries.
	"query-concurrency"?: int & >= 0 | *0

	// Initial bytes of memory allocated for a query.
	"query-initial-memory-bytes"?: int & >= 0

	// Maximum total bytes of memory allowed for queries.
	"query-max-memory-bytes"?: int & >= 0

	// Maximum bytes of memory allowed for a single query.
	"query-memory-bytes"?: int & >= 0

	// Maximum number of queries allowed in execution queue. When queue limit is reached, new queries are rejected. Setting to 0 allows an unlimited number of queries in the queue.
	"query-queue-size"?: int & >= 0 | *0

	// Disables sending telemetry data to InfluxData. The InfluxData telemetry page provides information about what data is collected and how InfluxData uses it.
	"reporting-disabled"?: bool & false | true | *false

	// Specifies the data store for secrets such as passwords and tokens. Store secrets in either the InfluxDB internal BoltDB or in Vault.
	"secret-store"?: string & "bolt" & "vault" | *"bolt"

	// Specifies the Time to Live (TTL) in minutes for newly created user sessions.
	"session-length"?: int & >= 0 | *60

	// Disables automatically extending a user’s session TTL on each request. By default, every request sets the session’s expiration time to five minutes from now. When disabled, sessions expire after the specified session length and the user is redirected to the login page, even if recently active.
	"session-renew-disabled"?: bool & false | true | *false

	// Path to the SQLite database file. The SQLite database is used to store metadata for notebooks and annotations.
	"sqlite-path"?: string

	// Maximum size (in bytes) a shard’s cache can reach before it starts rejecting writes.
	"storage-cache-max-memory-size"?: int & >= 0 | *1073741824

	// Size (in bytes) at which the storage engine will snapshot the cache and write it to a TSM file to make more memory available.
	"storage-cache-snapshot-memory-size"?: int & >= 0 | *26214400

	// Duration at which the storage engine will snapshot the cache and write it to a new TSM file if the shard hasn’t received writes or deletes.
	"storage-cache-snapshot-write-cold-duration"?: string | *"10m"

	// Duration at which the storage engine will compact all TSM files in a shard if it hasn’t received writes or deletes.
	"storage-compact-full-write-cold-duration"?: string | *"4h"

	// Rate limit (in bytes per second) that TSM compactions can write to disk.
	"storage-compact-throughput-burst"?: int & >= 0 | *50331648

	// Maximum number of full and level compactions that can run concurrently. A value of 0 results in 50% of runtime.GOMAXPROCS(0) used at runtime. Any number greater than zero limits compactions to that value. This setting does not apply to cache snapshotting.
	"storage-max-concurrent-compactions"?: int & >= 0 | *0

	// Size (in bytes) at which an index write-ahead log (WAL) file will compact into an index file. Lower sizes will cause log files to be compacted more quickly and result in lower heap usage at the expense of write throughput.
	"storage-max-index-log-file-size"?: int & >= 0 | *1048576

	// Skip field size validation on incoming write requests.
	"storage-no-validate-field-size"?: bool & false | true | *false

	// Interval of retention policy enforcement checks.
	"storage-retention-check-interval"?: string | *"30m"

	// Maximum number of snapshot compactions that can run concurrently across all series partitions in a database.
	"storage-series-file-max-concurrent-snapshot-compactions"?: int & >= 0 | *0

	// Size of the internal cache used in the TSI index to store previously calculated series results. Cached results are returned quickly rather than needing to be recalculated when a subsequent query with the same tag key/value predicate is executed. Setting this value to 0 will disable the cache and may decrease query performance.
	"storage-series-id-set-cache-size"?: int & >= 0 | *100

	// The time before a shard group’s end-time that the successor shard group is created.
	"storage-shard-precreator-advance-period"?: string | *"30m"

	// Interval of pre-create new shards check.
	"storage-shard-precreator-check-interval"?: string | *"10m"

	// Inform the kernel that InfluxDB intends to page in mmap’d sections of TSM files.
	"storage-tsm-use-madv-willneed"?: bool & false | true | *false

	// Validate incoming writes to ensure keys have only valid unicode characters.
	"storage-validate-keys"?: bool & false | true | *false

	// Duration a write will wait before fsyncing. A duration greater than 0 batches multiple fsync calls. This is useful for slower disks or when WAL write contention is present.
	"storage-wal-fsync-delay"?: string | *"0s"

	// Maximum number writes to the WAL directory to attempt at the same time. Default the number of processing units available × 2.
	"storage-wal-max-concurrent-writes"?: int & >= 0 | *0

	// Maximum amount of time a write request to the WAL directory will wait when the maximum number of concurrent active writes to the WAL directory has been met. Set to 0 to disable the timeout.
	"storage-wal-max-write-delay"?: string | *"10m"

	// Maximum amount of time the storage engine will process a write request before timing out.
	"storage-write-timeout"?: string | *"10s"

	// Specifies the data store for REST resources.
	"store"?: string & "disk" | "memory" | *"disk"

	// Require passwords to have at least eight characters and include characters from at least three of the following four character classes:
	"strong-passwords"?: bool & false | true

	// Ensures the /api/v2/setup endpoint always returns true to allow onboarding. This configuration option is primarily used in continuous integration tests.
	"testing-always-allow-setup"?: bool & false | true | *false

	// Path to TLS certificate file. Requires the tls-key to be set.
	"tls-cert"?: string

	// Path to TLS key file. Requires the tls-cert to be set.
	"tls-key"?: string

	// Minimum accepted TLS version.
	"tls-min-version"?: string | *"1.2"

	// Restrict accepted TLS ciphers to:
	// ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
	// ECDHE_RSA_WITH_AES_128_GCM_SHA256
	// ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
	// ECDHE_RSA_WITH_AES_256_GCM_SHA384
	// ECDHE_ECDSA_WITH_CHACHA20_POLY1305
	// ECDHE_RSA_WITH_CHACHA20_POLY1305
	"tls-strict-ciphers"?: bool & false | true | *false

	// Enable tracing in InfluxDB and specifies the tracing type. Tracing is disabled by default.
	"tracing-type"?: string | *"log" | *"jaeger"

	// Disable the InfluxDB user interface (UI). The UI is enabled by default.
	"ui-disable"?: bool & false | true | *false

	// Specifies the address of the Vault server expressed as a URL and port. For example:
	"vault-addr"?: string

	// Specifies the path to a PEM-encoded CA certificate file on the local disk. This file is used to verify the Vault server’s SSL certificate. This setting takes precedence over the --vault-capath setting.
	"vault-cacert"?: string

	// Specifies the path to a directory of PEM-encoded CA certificate files on the local disk. These certificates are used to verify the Vault server’s SSL certificate.
	"vault-capath"?: string

	// Specifies the path to a PEM-encoded client certificate on the local disk. This file is used for TLS communication with the Vault server.
	"vault-client-cert"?: string

	// Specifies the path to an unencrypted, PEM-encoded private key on disk which corresponds to the matching client certificate.
	"vault-client-key"?: string

	// Specifies the maximum number of retries when encountering a 5xx error code. The default is 2 (for three attempts in total). Set this to 0 or less to disable retrying.
	"vault-max-retries"?: int & >=0 | *2

	// Specifies the Vault client timeout.
	"vault-client-timeout"?: string | *"60s"

	// Skip certificate verification when communicating with Vault. Setting this variable voids Vault’s security model and is not recommended.
	"vault-skip-verify"?: bool & false | true | *false

	// Specifies the name to use as the Server Name Indication (SNI) host when connecting via TLS.
	"vault-tls-server-name"?: string

	// Specifies the Vault token use when authenticating with Vault.
	"vault-token"?: string
}

configuration: #InfluxdbParameter & {

}