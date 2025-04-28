etcdParameter: {
    // Human-readable name for this member.
    name?: string

    // Path to the data directory.
    dataDir?: string

    // Path to the dedicated wal directory.
    walDir?: string

    // Number of committed transactions to trigger a snapshot to disk.
    snapshotCount?: int | *10000

    // Time (in milliseconds) of a heartbeat interval.
    heartbeatInterval?: int | *100

    // Time (in milliseconds) for an election to timeout.
    electionTimeout?: int | *1000

    // Raise alarms when backend size exceeds the given quota. 0 means use the default quota.
    quotaBackendBytes?: int | *0

    // List of comma-separated URLs to listen on for peer traffic.
    listenPeerUrls?: [...string] | *["http://localhost:2380"]

    // List of comma-separated URLs to listen on for client traffic.
    listenClientUrls?: [...string] | *["http://localhost:2379"]

    // Maximum number of snapshot files to retain (0 is unlimited).
    maxSnapshots?: int | *5

    // Maximum number of wal files to retain (0 is unlimited).
    maxWals?: int | *5

    // Comma-separated white list of origins for CORS (cross-origin resource sharing).
    cors?: [...string] | *[]

    // List of this member's peer URLs to advertise to the rest of the cluster.
    initialAdvertisePeerUrls?: [...string] | *["http://localhost:2380"]

    // List of this member's client URLs to advertise to the public.
    advertiseClientUrls?: [...string] | *["http://localhost:2379"]

    // Discovery URL used to bootstrap the cluster.
    discovery?: string

    // Valid values include 'exit', 'proxy'.
    discoveryFallback?: *"proxy" | "exit"

    // HTTP proxy to use for traffic to discovery service.
    discoveryProxy?: string

    // DNS domain used to bootstrap initial cluster.
    discoverySrv?: string

    // Comma-separated string of initial cluster configuration for bootstrapping.
    initialCluster?: [...string]

    // Initial cluster token for the etcd cluster during bootstrap.
    initialClusterToken?: string | *"etcd-cluster"

    // Initial cluster state ('new' or 'existing').
    initialClusterState?: *"new" | "existing"

    // Reject reconfiguration requests that would cause quorum loss.
    strictReconfigCheck?: bool | *false

    // Enable runtime profiling data via HTTP server.
    enablePprof?: bool | *true

    // Valid values include 'on', 'readonly', 'off'.
    proxy?: *"off" | "on" | "readonly"

    // Time (in milliseconds) an endpoint will be held in a failed state.
    proxyFailureWait?: int | *5000

    // Time (in milliseconds) of the endpoints refresh interval.
    proxyRefreshInterval?: int | *30000

    // Time (in milliseconds) for a dial to timeout.
    proxyDialTimeout?: int | *1000

    // Time (in milliseconds) for a write to timeout.
    proxyWriteTimeout?: int | *5000

    // Time (in milliseconds) for a read to timeout.
    proxyReadTimeout?: int | *0

    clientTransportSecurity?: {
        // Path to the client server TLS cert file.
        certFile?: string

        // Path to the client server TLS key file.
        keyFile?: string

        // Enable client cert authentication.
        clientCertAuth?: bool | *false

        // Path to the client server TLS trusted CA cert file.
        trustedCaFile?: string

        // Client TLS using generated certificates.
        autoTls?: bool | *false
    }

    peerTransportSecurity?: {
        // Path to the peer server TLS cert file.
        certFile?: string

        // Path to the peer server TLS key file.
        keyFile?: string

        // Enable peer client cert authentication.
        clientCertAuth?: bool | *false

        // Path to the peer server TLS trusted CA cert file.
        trustedCaFile?: string

        // Peer TLS using generated certificates.
        autoTls?: bool | *false

        // Allowed CN for inter-peer authentication.
        allowedCn?: string

        // Allowed TLS hostname for inter-peer authentication.
        allowedHostname?: string
    }

    // The validity period of the self-signed certificate, the unit is year.
    selfSignedCertValidity?: int | *1

    // Enable debug-level logging for etcd.
    logLevel?: *"debug" | "info" | "warn" | "error"

    logger?: *"zap" | "capnslog"

    // Specify 'stdout' or 'stderr' to skip journald logging even when running under systemd.
    logOutputs?: [...string] | *["stderr"]

    // Force to create a new one-member cluster.
    forceNewCluster?: bool | *false

    autoCompactionMode?: *"periodic" | "revision"

    autoCompactionRetention?: string | *"1"

    // Limit etcd to a specific set of TLS cipher suites.
    cipherSuites?: [...string] | *[
        "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
        "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
    ]

    // Limit etcd to specific TLS protocol versions.
    tlsMinVersion?: *"TLS1.2" | "TLS1.3"
    tlsMaxVersion?: *"TLS1.3" | "TLS1.2"
}