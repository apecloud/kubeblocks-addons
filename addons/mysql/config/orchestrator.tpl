{{- $meta_mysql_from_service_ref := fromJson "{}" }}
{{- if index $.component "serviceReferences" }}
  {{- range $i, $e := $.component.serviceReferences }}
    {{- if eq $i "metaMysql" }}
      {{- $meta_mysql_from_service_ref = $e }}
      {{- break }}
    {{- end }}
  {{- end }}
{{- end }}
{
  "MySQLTopologyCredentialsConfigFile": "/usr/local/share/orchestrator/templates/orc-topology.cnf",
  "MySQLTopologySSLPrivateKeyFile": "",
  "MySQLTopologySSLCertFile": "",
  "MySQLTopologySSLCAFile": "",
  "MySQLTopologySSLSkipVerify": true,
  "MySQLTopologyUseMutualTLS": false,
  {{- $endpoint :=  splitList ":" $meta_mysql_from_service_ref.spec.endpoint.value | first }}
  "MySQLOrchestratorHost": {{- printf " \"%s\""   $endpoint}},
  "MySQLOrchestratorPort": {{- printf " %s" $meta_mysql_from_service_ref.spec.port.value }},
  "MySQLOrchestratorDatabase": "orchestrator",
  "MySQLOrchestratorCredentialsConfigFile": "/usr/local/share/orchestrator/templates/orc-backend.cnf",

  "DetectClusterAliasQuery": "select ifnull(max(cluster_name), '') as cluster_alias from kb_orc_meta_cluster.kb_orc_meta_cluster where anchor=1",
  "ApplyMySQLPromotionAfterMasterFailover": true,
  "Debug": false,
  "DetachLostReplicasAfterMasterFailover": true,
  "FailMasterPromotionIfSQLThreadNotUpToDate": true,
  "MySQLOrchestratorRejectReadOnly": true,

  "AutoPseudoGTID": true,
  "HTTPAdvertise": "http://orc-cluster-mysql:80",

  "HostnameResolveMethod": "none",
  "MySQLHostnameResolveMethod": "@@report_host",
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
}