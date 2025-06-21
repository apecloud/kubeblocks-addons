// etcd configuration constraint definition
#EtcdParameter: {
	// ========== IMMUTABLE PARAMETERS ==========
	// These parameters are managed by scripts/templates and cannot be modified by users

	// Node identifier (set by start.sh)
	name?: string | *"default"

	// Data directory path (set by etcd.conf.yaml.tpl)
	"data-dir"?: string | *"/var/lib/etcd"

	// Network listening configuration (set by etcd.conf.yaml.tpl)
	"listen-peer-urls"?:   string | *"http://0.0.0.0:2380"
	"listen-client-urls"?: string | *"http://0.0.0.0:2379"

	// Network advertising configuration (set by start.sh)
	"initial-advertise-peer-urls"?: string
	"advertise-client-urls"?:       string

	// Cluster initialization (set by etcd.conf.yaml.tpl and data-load.sh)
	"initial-cluster"?:       string
	"initial-cluster-token"?: string
	"initial-cluster-state"?: string & ("new" | "existing") | *"new"

	// Cluster management (immutable after creation)
	"force-new-cluster"?: bool | *false

	// TLS configuration (set by etcd.conf.yaml.tpl when TLS enabled)
	"client-transport-security"?: {
		"cert-file"?:        string
		"key-file"?:         string
		"client-cert-auth"?: bool | *false
		"trusted-ca-file"?:  string
		"auto-tls"?:         bool | *false
	}

	"peer-transport-security"?: {
		"cert-file"?:        string
		"key-file"?:         string
		"client-cert-auth"?: bool | *false
		"trusted-ca-file"?:  string
		"auto-tls"?:         bool | *false
		"allowed-cn"?:       string
		"allowed-hostname"?: string
	}

	// ========== STATIC PARAMETERS ==========
	// These parameters require etcd restart to take effect and can be configured by users

	// WAL directory path
	"wal-dir"?: string

	// Snapshot configuration
	"snapshot-count"?: int & >=1000 & <=1000000 | *10000
	"max-snapshots"?:  int & >=1 & <=100 | *5
	"max-wals"?:       int & >=1 & <=100 | *5

	// Cluster timing configuration
	"heartbeat-interval"?:  int & >=50 & <=1000 | *100
	"election-timeout"?:    int & >=500 & <=10000 | *1000
	"quota-backend-bytes"?: int & >=0 | *0

	// Cluster behavior
	"strict-reconfig-check"?: bool | *true

	// Logging configuration
	"log-level"?:   string & ("debug" | "info" | "warn" | "error" | "panic" | "fatal") | *"info"
	"logger"?:      string & ("capnslog" | "zap") | *"zap"
	"log-outputs"?: [...string] | *["stderr"]

	// Performance configuration
	"enable-pprof"?:              bool | *true
	"auto-compaction-mode"?:      string & ("periodic" | "revision") | *"periodic"
	"auto-compaction-retention"?: string | *"1"

	// Proxy configuration
	"proxy"?:                  string & ("off" | "readonly" | "on") | *"off"
	"proxy-failure-wait"?:     int & >=1000 & <=60000 | *5000
	"proxy-refresh-interval"?: int & >=1000 & <=60000 | *30000
	"proxy-dial-timeout"?:     int & >=1000 & <=60000 | *1000
	"proxy-write-timeout"?:    int & >=1000 & <=60000 | *5000
	"proxy-read-timeout"?:     int & >=0 & <=60000 | *0

	// Security configuration
	"cors"?:                      string
	"self-signed-cert-validity"?: int & >=1 & <=10 | *1

	// TLS cipher suites
	"cipher-suites"?: [...string]
	"tls-min-version"?: string & ("TLS1.0" | "TLS1.1" | "TLS1.2" | "TLS1.3") | *"TLS1.2"
	"tls-max-version"?: string & ("TLS1.0" | "TLS1.1" | "TLS1.2" | "TLS1.3") | *"TLS1.3"

	// Discovery configuration
	"discovery"?:          string
	"discovery-fallback"?: string & ("exit" | "proxy") | *"proxy"
	"discovery-proxy"?:    string
	"discovery-srv"?:      string
	...
}

configuration: #EtcdParameter & {

}
