// etcd configuration constraint definition
#EtcdParameter: {
	// ========== MEMBER PARAMETERS ==========
	// Basic member configuration

	// Human-readable name for this member
	name?: string | *"default"

	// Path to the data directory
	"data-dir"?: string | *"/var/run/etcd/default.etcd"

	// Path to the dedicated wal directory (empty = use /var/run/etcd/default.etcd/member/wal)
	"wal-dir"?: string | *"/var/run/etcd/default.etcd/member/wal"

	// Time (in milliseconds) of a heartbeat interval.
	"heartbeat-interval"?: uint & >=50 & <=5000 | *100

	// Time (in milliseconds) for an election to timeout. See tuning documentation for details.
	"election-timeout"?: uint & >=500 & <=50000 | *1000

	// Whether to fast-forward initial election ticks on boot for faster election.
	"initial-election-tick-advance"?: bool | *true

	// List of URLs to listen on for peer traffic
	"listen-peer-urls"?: string | *"http://localhost:2380"

	// List of URLs to listen on for client grpc traffic and http
	"listen-client-urls"?: string | *"http://localhost:2379"

	// List of URLs to listen on for http only client traffic
	"listen-client-http-urls"?: string | *""

	// List of this member's peer URLs to advertise to the rest of the cluster
	"initial-advertise-peer-urls"?: string | *"http://localhost:2380"

	// List of this member's client URLs to advertise to the public
	"advertise-client-urls"?: string | *"http://localhost:2379"

	// Number of committed transactions to trigger a snapshot to disk.
	// NOTE: default changed from 100000 (v3.5) to 10000 (v3.6)
	"snapshot-count"?: uint & >=1000 & <=1000000 | *10000

	// Maximum number of snapshot files to retain (0 is unlimited).
	"max-snapshots"?: uint & >=0 & <=100 | *5

	// Maximum number of wal files to retain (0 is unlimited).
	"max-wals"?: uint & >=0 & <=100 | *5

	// Raise alarms when backend size exceeds the given quota (0 defaults to low space quota).
	"quota-backend-bytes"?: uint & >=0 | *0

	// BackendFreelistType specifies the type of freelist that boltdb backend uses(array and map are supported types).
	"backend-bbolt-freelist-type"?: string & ("map" | "array") | *"map"

	// BackendBatchInterval is the maximum time before commit the backend transaction.
	"backend-batch-interval"?: string | *""

	// BackendBatchLimit is the maximum operations before commit the backend transaction.
	"backend-batch-limit"?: uint & >=0 | *0

	// Maximum number of operations permitted in a transaction.
	"max-txn-ops"?: uint & >=1 & <=10000 | *128

	// Maximum client request size in bytes the server will accept.
	"max-request-bytes"?: uint & >=1024 & <=33554432 | *1572864

	// Minimum duration interval that a client should wait before pinging server
	"grpc-keepalive-min-time"?: string | *"5s"

	// Frequency duration of server-to-client ping to check if a connection is alive (0 to disable)
	"grpc-keepalive-interval"?: string | *"2h"

	// Additional duration of wait before closing a non-responsive connection (0 to disable)
	"grpc-keepalive-timeout"?: string | *"20s"

	// Enable to set socket option SO_REUSEPORT on listeners allowing rebinding of a port already in use
	"socket-reuse-port"?: bool | *false

	// Enable to set socket option SO_REUSEADDR on listeners allowing binding to an address in TIME_WAIT state
	"socket-reuse-address"?: bool | *false

	// ========== CLUSTERING PARAMETERS ==========

	// Discovery URL used to bootstrap the cluster
	"discovery"?: string | *""

	// Expected behavior ('exit' or 'proxy') when discovery services fails
	"discovery-fallback"?: string & ("exit" | "proxy") | *"proxy"

	// HTTP proxy to use for traffic to discovery service
	"discovery-proxy"?: string | *""

	// DNS srv domain used to bootstrap the cluster
	"discovery-srv"?: string | *""

	// Suffix to the dns srv name queried when bootstrapping
	"discovery-srv-name"?: string | *""

	// Initial cluster configuration for bootstrapping
	"initial-cluster"?: string | *"default=http://localhost:2380"

	// Initial cluster state ('new' or 'existing')
	"initial-cluster-state"?: string & ("new" | "existing") | *"new"

	// Initial cluster token for the etcd cluster during bootstrap
	"initial-cluster-token"?: string | *"etcd-cluster"

	// Reject reconfiguration requests that would cause quorum loss
	"strict-reconfig-check"?: bool | *true

	// Enable the raft Pre-Vote algorithm to prevent disruption
	"pre-vote"?: bool | *true

	// Auto compaction retention length. 0 means disable auto compaction
	"auto-compaction-retention"?: string | *"1"

	// Interpret 'auto-compaction-retention' as 'periodic' or 'revision'
	"auto-compaction-mode"?: string & ("periodic" | "revision") | *"periodic"

	// Accept etcd V2 client requests. Deprecated and to be decommissioned in v3.6
	"enable-v2"?: bool | *false

	// Phase of v2store deprecation
	"v2-deprecation"?: string & ("not-yet" | "write-only" | "write-only-drop-data" | "gone") | *"not-yet"

	// TLS configuration is handled through nested structures below
	// (removed duplicate top-level TLS fields to avoid confusion)

	// The validity period of the client and peer certificates that are automatically generated by etcd when you specify ClientAutoTLS and PeerAutoTLS, the unit is year, and the default is 1.
	"self-signed-cert-validity"?: uint & >=1 & <=10 | *1

	// Comma-separated list of supported TLS cipher suites
	"cipher-suites"?: [...string] | *["TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256", "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"]

	// Minimum TLS version supported by etcd
	"tls-min-version"?: string & ("TLS1.0" | "TLS1.1" | "TLS1.2" | "TLS1.3") | *"TLS1.2"

	// Maximum TLS version supported by etcd
	"tls-max-version"?: string & ("TLS1.0" | "TLS1.1" | "TLS1.2" | "TLS1.3" | "") | *"TLS1.3"

	// Comma-separated whitelist of origins for CORS (cross-origin resource sharing)
	"cors"?: string | *""

	// Acceptable hostnames from HTTP client requests, if server is not secure
	"host-whitelist"?: string | *"*"

	// ========== AUTHENTICATION PARAMETERS ==========

	// Specify a v3 authentication token type and its options ('simple' or 'jwt').
	"auth-token"?: string & ("simple" | "jwt") | *"simple"

	// Specify the cost / strength of the bcrypt algorithm for hashing auth passwords. Valid values are between 4 and 31.
	"bcrypt-cost"?: uint & >=4 & <=31 | *10

	// Time (in seconds) of the auth-token-ttl.
	"auth-token-ttl"?: uint & >=1 & <=86400 | *300

	// ========== PROFILING AND MONITORING PARAMETERS ==========

	// Enable runtime profiling data via HTTP server
	"enable-pprof"?: bool | *true

	// Set level of detail for exported metrics
	"metrics"?: string & ("basic" | "extensive") | *"basic"

	// List of URLs to listen on for the metrics and health endpoints
	"listen-metrics-urls"?: string | *""

	// ========== NESTED TLS CONFIGURATION STRUCTURES ==========
	// These nested structures are used by etcd.conf.yaml.tpl template
	// for backward compatibility with etcd v2 configuration format

	// Client TLS transport security configuration
	"client-transport-security"?: {
		// Path to the client server TLS cert file (must be absolute path if specified)
		"cert-file"?: string | *""
		
		// Path to the client server TLS key file (must be absolute path if specified)
		"key-file"?: string | *""
		
		// Enable client cert authentication
		"client-cert-auth"?: bool | *false
		
		// Path to the client server TLS trusted CA cert file (must be absolute path if specified)
		"trusted-ca-file"?: string | *""
		
		// Client TLS using generated certificates (incompatible with cert-file/key-file)
		"auto-tls"?: bool | *false
	}

	// Peer TLS transport security configuration
	"peer-transport-security"?: {
		// Path to the peer server TLS cert file (must be absolute path if specified)
		"cert-file"?: string | *""
		
		// Path to the peer server TLS key file (must be absolute path if specified)
		"key-file"?: string | *""
		
		// Enable peer client cert authentication
		"client-cert-auth"?: bool | *false
		
		// Path to the peer server TLS trusted CA file (must be absolute path if specified)
		"trusted-ca-file"?: string | *""
		
		// Peer TLS using self-generated certificates (incompatible with cert-file/key-file)
		"auto-tls"?: bool | *false
		
		// Required CN for client certs connecting to the peer endpoint (comma-separated list)
		"allowed-cn"?: string | *""
		
		// Allowed TLS hostname for inter peer authentication (comma-separated list)
		"allowed-hostname"?: string | *""
	}

	// ========== UNSAFE FEATURES PARAMETERS ==========
	// Warning: using unsafe features may break the guarantees given by the consensus protocol!

	// Force to create a new one-member cluster.
	"force-new-cluster"?: bool | *false

	// Disables fsync, unsafe, will cause data loss.
	"unsafe-no-fsync"?: bool | *false

	// ========== LOGGING PARAMETERS ==========

	// Currently only supports 'zap' for structured logging
	"logger"?: string & ("zap") | *"zap"

	// Specify 'stdout' or 'stderr' to skip journald logging even when running under systemd
	"log-outputs"?: [...string] | *["stderr"]

	// Configures log level
	"log-level"?: string & ("debug" | "info" | "warn" | "error" | "panic" | "fatal") | *"info"

	// Configures log format. Only supports json, console
	// NOTE: log-format is new in v3.6, ignored by v3.5
	"log-format"?: string & ("json" | "console") | *"json"

	// Enable log rotation of a single log-outputs file target
	"enable-log-rotation"?: bool | *false

	// Configures log rotation if enabled with a JSON logger config
	"log-rotation-config-json"?: string | *"{\"maxsize\": 100, \"maxage\": 0, \"maxbackups\": 0, \"localtime\": false, \"compress\": false}"

	// ========== EXPERIMENTAL DISTRIBUTED TRACING PARAMETERS ==========

	// Enable experimental distributed tracing.
	"experimental-enable-distributed-tracing"?: bool | *false

	// Distributed tracing collector address.
	"experimental-distributed-tracing-address"?: string | *"localhost:4317"

	// Distributed tracing service name, must be same across all etcd instances.
	"experimental-distributed-tracing-service-name"?: string | *"etcd"

	// Distributed tracing instance ID, must be unique per each etcd instance.
	"experimental-distributed-tracing-instance-id"?: string | *""

	// Number of samples to collect per million spans for OpenTelemetry Tracing (if enabled with experimental-enable-distributed-tracing flag).
	"experimental-distributed-tracing-sampling-rate"?: uint & >=0 & <=1000000 | *0

	// ========== V2 PROXY PARAMETERS ==========
	// Note: flags will be deprecated in v3.6.

	// Proxy mode setting ('off', 'readonly' or 'on').
	"proxy"?: string & ("off" | "readonly" | "on") | *"off"

	// Time (in milliseconds) an endpoint will be held in a failed state.
	"proxy-failure-wait"?: uint & >=1000 & <=300000 | *5000

	// Time (in milliseconds) of the endpoints refresh interval.
	"proxy-refresh-interval"?: uint & >=1000 & <=300000 | *30000

	// Time (in milliseconds) for a dial to timeout.
	"proxy-dial-timeout"?: uint & >=1000 & <=60000 | *1000

	// Time (in milliseconds) for a write to timeout.
	"proxy-write-timeout"?: uint & >=1000 & <=60000 | *5000

	// Time (in milliseconds) for a read to timeout.
	"proxy-read-timeout"?: uint & >=0 & <=60000 | *0

	// ========== EXPERIMENTAL FEATURES PARAMETERS ==========

	// Enable to check data corruption before serving any client/peer traffic.
	"experimental-initial-corrupt-check"?: bool | *false

	// Duration of time between cluster corruption check passes.
	"experimental-corrupt-check-time"?: string | *"0s"

	// Serve v2 requests through the v3 backend under a given prefix. Deprecated and to be decommissioned in v3.6.
	"experimental-enable-v2v3"?: string | *""

	// ExperimentalEnableLeaseCheckpoint enables primary lessor to persist lease remainingTTL to prevent indefinite auto-renewal of long lived leases.
	"experimental-enable-lease-checkpoint"?: bool | *false

	// ExperimentalCompactionBatchLimit sets the maximum revisions deleted in each compaction batch.
	"experimental-compaction-batch-limit"?: uint & >=1 & <=10000 | *1000

	// Skip verification of SAN field in client certificate for peer connections.
	"experimental-peer-skip-client-san-verification"?: bool | *false

	// Duration of periodical watch progress notification.
	"experimental-watch-progress-notify-interval"?: string | *"10m"

	// Warning is generated if requests take more than this duration.
	"experimental-warning-apply-duration"?: string | *"100ms"

	// Enable the write transaction to use a shared buffer in its readonly check operations.
	"experimental-txn-mode-write-with-shared-buffer"?: bool | *true

	// Enable the defrag during etcd server bootstrap on condition that it will free at least the provided threshold of disk space. Needs to be set to non-zero value to take effect.
	"experimental-bootstrap-defrag-threshold-megabytes"?: uint & >=0 | *0

	// other parameters
	...
}

configuration: #EtcdParameter & {

}
