{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
<clickhouse>
  <!-- Macros -->
  <macros>
    <shard from_env="CLICKHOUSE_SHARD_ID"></shard>
    <replica from_env="CLICKHOUSE_REPLICA_ID"></replica>
    <layer>{{ $clusterName }}</layer>
  </macros>
  <!-- Log Level -->
  <logger>
    <level>information</level>
  </logger>
  <!-- Cluster configuration - Any update of the shards and replicas requires helm upgrade -->
  <remote_servers>
    <default>
      <shard>
    {{- range $_, $host := splitList "," .CLICKHOUSE_POD_FQDN_LIST }}
        <replica>
            <host>{{ $host }}</host>
            <port>9000</port>
        </replica>
    {{- end }}
      </shard>
    </default>
  </remote_servers>
  {{- if (index . "CH_KEEPER_POD_FQDN_LIST") -}}
  <!-- Zookeeper configuration -->
  <zookeeper>
    {{- range $_, $host := splitList "," .CH_KEEPER_POD_FQDN_LIST }}
    <node>
      <host>{{ $host }}</host>
      <port>2181</port>
    </node>
    {{- end }}
  </zookeeper>
  {{- end }}
  <!-- Prometheus metrics -->
  <prometheus>
    <endpoint>/metrics</endpoint>
    <port from_env="CLICKHOUSE_METRICS_PORT"></port>
    <metrics>true</metrics>
    <events>true</events>
    <asynchronous_metrics>true</asynchronous_metrics>
  </prometheus>
</clickhouse>
