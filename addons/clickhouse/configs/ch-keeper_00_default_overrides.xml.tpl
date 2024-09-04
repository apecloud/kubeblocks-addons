{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
<clickhouse>
  <listen_host>0.0.0.0</listen_host>
  <keeper_server>
      <tcp_port from_env="CLICKHOUSE_KEEPER_TCP_PORT"></tcp_port>
      <server_id>1</server_id>
      <log_storage_path>/var/lib/clickhouse/coordination/log</log_storage_path>
      <snapshot_storage_path>/var/lib/clickhouse/coordination/snapshots</snapshot_storage_path>
      <coordination_settings>
          <operation_timeout_ms>10000</operation_timeout_ms>
          <session_timeout_ms>30000</session_timeout_ms>
          <raft_logs_level>warning</raft_logs_level>
      </coordination_settings>
      <raft_configuration>
{{- range $id, $host := splitList "," .CH_KEEPER_POD_FQDN_LIST }}
        <server>
          <id>{{ $id | add1 }}</id>
          <hostname>{{ $host }}</hostname>
          <port from_env="CLICKHOUSE_KEEPER_RAFT_PORT"></port>
        </server>
{{- end }}
      </raft_configuration>
  </keeper_server>
  <!-- Prometheus metrics -->
  <prometheus>
      <endpoint>/metrics</endpoint>
      <port from_env="CLICKHOUSE_METRICS_PORT"></port>
      <metrics>true</metrics>
      <events>true</events>
      <asynchronous_metrics>true</asynchronous_metrics>
  </prometheus>
</clickhouse>