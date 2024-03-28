{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}

{
  "MySQLTopologyCredentialsConfigFile": "/usr/local/share/orchestrator/templates/orc-topology.cnf",
  "MySQLTopologySSLPrivateKeyFile": "",
  "MySQLTopologySSLCertFile": "",
  "MySQLTopologySSLCAFile": "",
  "MySQLTopologySSLSkipVerify": true,
  "MySQLTopologyUseMutualTLS": false,

  "MySQLOrchestratorHost": {{ $mysql_meta_service_host }}
  "MySQLOrchestratorPort": 3306,
  "MySQLOrchestratorDatabase": "orchestrator",
  "MySQLOrchestratorUser": {{ $mysql_meta_user }},
  "MySQLOrchestratorPassword": {{ $mysql_meta_password }},

  "ApplyMySQLPromotionAfterMasterFailover": true,
  "Debug": false,
  "DetachLostReplicasAfterMasterFailover": true,
  "MySQLHostnameResolveMethod": "",
  "FailMasterPromotionIfSQLThreadNotUpToDate": true,

  "AutoPseudoGTID": true,


  "HTTPAdvertise": "http://orc-cluster-mysql:80",

  "HostnameResolveMethod": "none",
  "InstancePollSeconds": 5,
  "ListenAddress": ":3000",
  "MasterFailoverLostInstancesDowntimeMinutes": 10,

  "DiscoverByShowSlaveHosts": false,
  "FailureDetectionPeriodBlockMinutes": 60,

  "ProcessesShellCommand": "sh",

  "RecoverIntermediateMasterClusterFilters": [
    ".*"
  ],
  "RecoverMasterClusterFilters": [
    ".*"
  ],
  "RecoveryIgnoreHostnameFilters": [],
  "RecoveryPeriodBlockSeconds": 300,
  "RemoveTextFromHostnameDisplay": ":3306",
  "UnseenInstanceForgetHours": 1,

  "OnFailureDetectionProcesses": [
    "echo 'Detected {failureType} on {failureCluster}. Affected replicas: {countReplicas}' >> /tmp/recovery.log"
  ]

  "PreGracefulTakeoverProcesses": [
    "echo 'Planned takeover about to take place on {failureCluster}. Master will switch to read_only' >> /tmp/recovery.log"
  ],
  "PreFailoverProcesses": [
    "echo 'Will recover from {failureType} on {failureCluster}' >> /tmp/recovery.log"
  ],
  "PostFailoverProcesses": [
    "echo '(for all types) Recovered from {failureType} on {failureCluster}. Failed: {failedHost}:{failedPort}; Successor: {successorHost}:{successorPort}' >> /tmp/recovery.log"
  ],
  "PostUnsuccessfulFailoverProcesses": [],
  "PostMasterFailoverProcesses": [
    "echo 'Recovered from {failureType} on {failureCluster}. Failed: {failedHost}:    {failedPort}; Promoted: {successorHost}:{successorPort}' >> /tmp/recovery.log"
  ],
  "PostIntermediateMasterFailoverProcesses": [],
  "PostGracefulTakeoverProcesses": [
    "echo 'Planned takeover complete' >> /tmp/recovery.log"
  ],
}