{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- $useZookeeper := true -}}
<clickhouse>
  <listen_host>0.0.0.0</listen_host>
  <keeper_server>
    {{- range $.cluster.spec.componentSpecs }}
      {{- $compIter := . }}
      {{- if (eq $compIter.componentDef "clickhouse-keeper") }}
        {{- $useZookeeper = false }}
      {{- end }}
    {{- end }}

    {{- if $.component.tlsConfig }}
    {{- if eq $useZookeeper false }}
    <tcp_port_secure replace="replace" from_env="CLICKHOUSE_KEEPER_TCP_TLS_PORT"/>
    {{- else }}
    <tcp_port replace="replace" from_env="ZOOKEEPER_TCP_TLS_PORT"/>
    {{- end }}
    <secure>1</secure>
    {{- else }}
    {{- if eq $useZookeeper false }}
    <tcp_port_secure replace="replace" from_env="CLICKHOUSE_KEEPER_TCP_PORT"/>
    {{- else }}
    <tcp_port replace="replace" from_env="ZOOKEEPER_TCP_PORT"/>
    {{- end }}
    {{- end }}
    {{/*	TODO change server_id for each server	*/}}
    <server_id>1</server_id>
    <log_storage_path>/var/lib/clickhouse/coordination/log</log_storage_path>
    <snapshot_storage_path>/var/lib/clickhouse/coordination/snapshots</snapshot_storage_path>
    <coordination_settings>
      <operation_timeout_ms>10000</operation_timeout_ms>
      <session_timeout_ms>30000</session_timeout_ms>
      <raft_logs_level>warning</raft_logs_level>
    </coordination_settings>
    <raft_configuration>
      {{- if $.component.tlsConfig }}
      <secure>true</secure>
      {{ end }}
      {{- $replicas := $.component.replicas | int }}
      {{- range $i, $e := until $replicas }}
      <server>
        <id>{{ $i | int }}</id>
        <hostname>{{ $clusterName }}-{{ $.component.name }}-{{ $i }}.{{ $clusterName }}-{{ $.component.name }}-headless.{{ $namespace }}.svc.{{- $.clusterDomain }}</hostname>
        {{- if $.component.tlsConfig }}
        <port replace="replace" from_env="CLICKHOUSE_KEEPER_RAFT_TLS_PORT"/>
        {{- else }}
        <port replace="replace" from_env="CLICKHOUSE_KEEPER_RAFT_PORT"/>
        {{- end }}
      </server>
      {{- end }}
    </raft_configuration>
  </keeper_server>
  <!-- Prometheus metrics -->
  <prometheus>
    <endpoint>/metrics</endpoint>
    <port replace="replace" from_env="CLICKHOUSE_METRICS_PORT"/>
    <metrics>true</metrics>
    <events>true</events>
    <asynchronous_metrics>true</asynchronous_metrics>
  </prometheus>
  <!-- tls configuration -->
  {{- if $.component.tlsConfig -}}
  {{- $CA_FILE := getCAFile -}}
  {{- $CERT_FILE := getCertFile -}}
  {{- $KEY_FILE := getKeyFile -}}
  <openSSL>
    <server>
      <certificateFile>{{$CERT_FILE}}</certificateFile>
      <privateKeyFile>{{$KEY_FILE}}</privateKeyFile>
      <!-- <dhParamsFile>/etc/clickhouse-server/dhparam.pem</dhParamsFile> -->
      <verificationMode>relaxed</verificationMode>
      <caConfig>{{$CA_FILE}}</caConfig>
      <cacheSessions>true</cacheSessions>
      <disableProtocols>sslv2,sslv3</disableProtocols>
      <preferServerCiphers>true</preferServerCiphers>
    </server>
    <client>
      <loadDefaultCAFile>false</loadDefaultCAFile>
      <caConfig>{{$CA_FILE}}</caConfig>
      <cacheSessions>true</cacheSessions>
      <disableProtocols>sslv2,sslv3</disableProtocols>
      <preferServerCiphers>true</preferServerCiphers>
      <verificationMode>relaxed</verificationMode>
      <invalidCertificateHandler>
        <name>RejectCertificateHandler</name>
      </invalidCertificateHandler>
    </client>
  </openSSL>
  {{- end }}
</clickhouse>