// etcd configuration constraint definition
#EtcdConfig: {
	// Node identifier
	name?: string | *"default"
	
	// Data directory path
	"data-dir"?: string | *"/var/lib/etcd"
	
	// WAL directory path
	"wal-dir"?: string
	
	// Snapshot configuration
	"snapshot-count"?: int & >=1000 & <=1000000 | *10000
	"max-snapshots"?: int & >=1 & <=100 | *5
	"max-wals"?: int & >=1 & <=100 | *5
	
	// Cluster timing configuration
	"heartbeat-interval"?: int & >=50 & <=1000 | *100
	"election-timeout"?: int & >=500 & <=10000 | *1000
	"quota-backend-bytes"?: int & >=0 | *0
	
	// Network listening configuration
	"listen-peer-urls"?: string | *"http://0.0.0.0:2380"
	"listen-client-urls"?: string | *"http://0.0.0.0:2379"
	"initial-advertise-peer-urls"?: string
	"advertise-client-urls"?: string
	
	// Cluster initialization
	"initial-cluster"?: string
	"initial-cluster-token"?: string
	"initial-cluster-state"?: string & ("new" | "existing") | *"new"
	"strict-reconfig-check"?: bool | *true
	
	// Logging configuration
	"log-level"?: string & ("debug" | "info" | "warn" | "error" | "panic" | "fatal") | *"info"
	"logger"?: string & ("capnslog" | "zap") | *"zap"
	"log-outputs"?: [...string] | *["stderr"]
	
	// Performance configuration
	"enable-pprof"?: bool | *true
	"auto-compaction-mode"?: string & ("periodic" | "revision") | *"periodic"
	"auto-compaction-retention"?: string | *"1"
	
	// Proxy configuration
	"proxy"?: string & ("off" | "readonly" | "on") | *"off"
	"proxy-failure-wait"?: int & >=1000 & <=60000 | *5000
	"proxy-refresh-interval"?: int & >=1000 & <=60000 | *30000
	"proxy-dial-timeout"?: int & >=1000 & <=60000 | *1000
	"proxy-write-timeout"?: int & >=1000 & <=60000 | *5000
	"proxy-read-timeout"?: int & >=0 & <=60000 | *0
	
	// Security configuration
	"cors"?: string
	"force-new-cluster"?: bool | *false
	"self-signed-cert-validity"?: int & >=1 & <=10 | *1
	
	// TLS configuration for client connections
	"client-transport-security"?: {
		"cert-file"?: string
		"key-file"?: string
		"client-cert-auth"?: bool | *false
		"trusted-ca-file"?: string
		"auto-tls"?: bool | *false
	}
	
	// TLS configuration for peer connections
	"peer-transport-security"?: {
		"cert-file"?: string
		"key-file"?: string
		"client-cert-auth"?: bool | *false
		"trusted-ca-file"?: string
		"auto-tls"?: bool | *false
		"allowed-cn"?: string
		"allowed-hostname"?: string
	}
	
	// TLS cipher suites
	"cipher-suites"?: [...string]
	"tls-min-version"?: string & ("TLS1.0" | "TLS1.1" | "TLS1.2" | "TLS1.3") | *"TLS1.2"
	"tls-max-version"?: string & ("TLS1.0" | "TLS1.1" | "TLS1.2" | "TLS1.3") | *"TLS1.3"
	
	// Discovery configuration
	"discovery"?: string
	"discovery-fallback"?: string & ("exit" | "proxy") | *"proxy"
	"discovery-proxy"?: string
	"discovery-srv"?: string
}

#EtcdParameter: {
	etcd: #EtcdConfig
}

configuration: #EtcdParameter & {
} 