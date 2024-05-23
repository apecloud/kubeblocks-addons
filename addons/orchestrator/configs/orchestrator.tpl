{
  "Debug": false,
  "ListenAddress": ":3000",

  "BackendDB": "${ORC_BACKEND_DB}",
  "SQLite3DataFile": "${ORC_WORKDIR}/sqlite/orchestrator.db",

  "MySQLTopologyCredentialsConfigFile": "/configs/orc-topology.cnf",
  "MySQLTopologySSLPrivateKeyFile": "",
  "MySQLTopologySSLCertFile": "",
  "MySQLTopologySSLCAFile": "",
  "MySQLTopologySSLSkipVerify": true,
  "MySQLTopologyUseMutualTLS": false,

  "MySQLOrchestratorHost": "${META_MYSQL_ENDPOINT}",
  "MySQLOrchestratorPort": ${META_MYSQL_PORT},
  "MySQLOrchestratorDatabase": "${ORC_META_DATABASE}",
  "MySQLOrchestratorCredentialsConfigFile": "/configs/orc-backend.cnf",

  "RaftEnabled": ${ORC_RAFT_ENABLED},
  "RaftDataDir": "${ORC_WORKDIR}/raft",
  "RaftBind": "${ORC_POD_NAME}",
  "DefaultRaftPort": 10008,
  "RaftNodes": [ ${ORC_PEERS} ],

  "ApplyMySQLPromotionAfterMasterFailover": true,
  "DetachLostReplicasAfterMasterFailover": true,
  "FailMasterPromotionIfSQLThreadNotUpToDate": true,
  "MySQLOrchestratorRejectReadOnly": true,

  "HostnameResolveMethod": "none",
  "MySQLHostnameResolveMethod": "@@report_host",
  "InstancePollSeconds": 5,

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
}