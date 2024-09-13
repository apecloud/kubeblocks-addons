{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
{{- $useZookeeper := true -}}
<clickhouse>
  <listen_host>0.0.0.0</listen_host>
  {{- if $.component.tlsConfig }}
  <https_port replace="replace" from_env="CLICKHOUSE_HTTPS_PORT"/>
  <tcp_port_secure replace="replace" from_env="CLICKHOUSE_TCP_SECURE_PORT"/>
  <interserver_https_port replace="replace" from_env="CLICKHOUSE_INTERSERVER_HTTPS_PORT"/>
  <http_port remove="remove"/>
  <tcp_port remove="remove"/>
  <interserver_http_port remove="remove"/>
  {{- else }}
  <http_port replace="replace" from_env="CLICKHOUSE_HTTP_PORT"/>
  <tcp_port replace="replace" from_env="CLICKHOUSE_TCP_PORT"/>
  <interserver_http_port replace="replace" from_env="CLICKHOUSE_INTERSERVER_HTTP_PORT"/>
  {{- end }}
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
    <server_id from_env="KEEPER_REPLICA_ID"/>
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
      {{- end }}
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
      <!--TODO add this speed up file <dhParamsFile>/etc/clickhouse-server/dhparam.pem</dhParamsFile> -->
      <verificationMode>relaxed</verificationMode>
      <caConfig>{{$CA_FILE}}</caConfig>
      <cacheSessions>true</cacheSessions>
      <disableProtocols>sslv2,sslv3</disableProtocols>
      <preferServerCiphers>true</preferServerCiphers>
    </server>
    <client>
      <loadDefaultCAFile>false</loadDefaultCAFile>
      <certificateFile>{{$CERT_FILE}}</certificateFile>
      <privateKeyFile>{{$KEY_FILE}}</privateKeyFile>
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
  <grpc>
    <enable_ssl>1</enable_ssl>
    <ssl_cert_file>{{$CERT_FILE}}</ssl_cert_file>
    <ssl_key_file>{{$KEY_FILE}}</ssl_key_file>
    <ssl_require_client_auth>true</ssl_require_client_auth>
    <ssl_ca_cert_file>{{$CA_FILE}}</ssl_ca_cert_file>
    <transport_compression_type>none</transport_compression_type>
    <transport_compression_level>0</transport_compression_level>
    <max_send_message_size>-1</max_send_message_size>
    <max_receive_message_size>-1</max_receive_message_size>
    <verbose_logs>false</verbose_logs>
  </grpc>
  {{- end }}
</clickhouse>