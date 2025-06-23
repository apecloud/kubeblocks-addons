// etcd configuration constraint definition
#EtcdParameter: {
	// ========== IMMUTABLE PARAMETERS ==========
	// These parameters are managed by scripts/templates and cannot be modified by users

	// Node identifier (set by start.sh)
	name?: string | *"default"

	// Network advertising configuration (set by start.sh)
	"initial-advertise-peer-urls"?: string
	"advertise-client-urls"?:       string

	// Data directory path (set by etcd.conf.yaml.tpl)
	"data-dir"?: string | *"/var/lib/etcd"

	// Network listening configuration (set by etcd.conf.yaml.tpl)
	"listen-peer-urls"?:   string | *"http://0.0.0.0:2380"
	"listen-client-urls"?: string | *"http://0.0.0.0:2379"

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

	// Cluster initialization (set by etcd.conf.yaml.tpl and data-load.sh)
	"initial-cluster"?:       string
	"initial-cluster-token"?: string
	"initial-cluster-state"?: string & ("new" | "existing") | *"new"

	// Cluster management (immutable)
	"force-new-cluster"?: bool | *false

	// ========== STATIC PARAMETERS ==========
	// These parameters require etcd restart to take effect and can be configured by users

	// WAL directory path
	"wal-dir"?: string

	// Snapshot configuration
	"snapshot-count"?: uint & >=1000 & <=1000000 | *10000
	"max-snapshots"?:  uint & >=1 & <=100 | *5
	"max-wals"?:       uint & >=1 & <=100 | *5

	// Cluster timing configuration
	"heartbeat-interval"?:  uint & >=50 & <=1000 | *100
	"election-timeout"?:    uint & >=500 & <=10000 | *1000
	"quota-backend-bytes"?: uint & >=0 | *0

	// Cluster behavior
	"strict-reconfig-check"?: bool | *true

	// Auto compaction configuration
	"auto-compaction-mode"?:      string & ("periodic" | "revision") | *"periodic"
	"auto-compaction-retention"?: string | *"1"

	// TLS cipher suites configuration
	"cipher-suites"?:    [...string]
	"tls-min-version"?:  string & ("TLS1.0" | "TLS1.1" | "TLS1.2" | "TLS1.3") | *"TLS1.2"
	"tls-max-version"?:  string & ("TLS1.0" | "TLS1.1" | "TLS1.2" | "TLS1.3") | *"TLS1.3"

	// Proxy configuration
	"proxy"?:                  string & ("off" | "readonly" | "on") | *"off"
	"proxy-failure-wait"?:     uint & >=1000 & <=60000 | *5000
	"proxy-refresh-interval"?: uint & >=1000 & <=60000 | *30000
	"proxy-dial-timeout"?:     uint & >=1000 & <=60000 | *1000
	"proxy-write-timeout"?:    uint & >=1000 & <=60000 | *5000
	"proxy-read-timeout"?:     uint & >=0 & <=60000 | *0

	// Performance configuration
	"enable-pprof"?: bool | *false

	// Security configuration
	"cors"?:                      string
	"self-signed-cert-validity"?: uint & >=1 & <=10 | *1

	// Discovery configuration
	"discovery"?:          string
	"discovery-fallback"?: string & ("exit" | "proxy") | *"proxy"
	"discovery-proxy"?:    string
	"discovery-srv"?:      string

	// Logging configuration
	"log-level"?:   string & ("debug" | "info" | "warn" | "error" | "panic" | "fatal") | *"info"
	"logger"?:      string & ("capnslog" | "zap") | *"zap"
	"log-outputs"?: [...string] | *["stderr"]

	...
}

configuration: #EtcdParameter & {

}
