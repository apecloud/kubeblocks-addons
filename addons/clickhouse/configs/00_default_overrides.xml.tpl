{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
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
  <!-- Macros, self defined -->
  <macros>
    <shard from_env="CLICKHOUSE_SHARD_ID"/>
    <replica from_env="CLICKHOUSE_REPLICA_ID"/>
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
          {{- if $.component.tlsConfig }}
          <port replace="replace" from_env="CLICKHOUSE_TCP_SECURE_PORT"/>
          <secure>1</secure>
          {{- else }}
          <port replace="replace" from_env="CLICKHOUSE_TCP_PORT"/>
          {{- end }}
        </replica>
        {{- end }}
      </shard>
    </default>
  </remote_servers>
  <!-- Zookeeper configuration -->
  <zookeeper>
    {{- range $_, $host := splitList "," .CH_KEEPER_POD_FQDN_LIST }}
    <node>
      <host>{{ $host }}</host>
      {{- if $.component.tlsConfig }}
      <port replace="replace" from_env="CLICKHOUSE_KEEPER_TCP_TLS_PORT"/>
      <secure>1</secure>
      {{- else }}
      <port replace="replace" from_env="CLICKHOUSE_KEEPER_TCP_PORT"/>
      {{- end }}
    </node>
    {{- end }}
  </zookeeper>
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
  {{- $KEY_FILE := getKeyFile }}
  <protocols>
    <prometheus_protocol>
      <type>prometheus</type>
      <description>prometheus protocol</description>
    </prometheus_protocol>
    <prometheus_secure>
      <type>tls</type>
      <impl>prometheus_protocol</impl>
      <description>prometheus over https</description>
      <certificateFile>{{$CERT_FILE}}</certificateFile>
      <privateKeyFile>{{$KEY_FILE}}</privateKeyFile>
    </prometheus_secure>
  </protocols>
  <openSSL>
    <server>
      <certificateFile>{{$CERT_FILE}}</certificateFile>
      <privateKeyFile>{{$KEY_FILE}}</privateKeyFile>
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
    <ssl_require_client_auth>false</ssl_require_client_auth>
    <ssl_ca_cert_file>{{$CA_FILE}}</ssl_ca_cert_file>
    <transport_compression_type>none</transport_compression_type>
    <transport_compression_level>0</transport_compression_level>
    <max_send_message_size>-1</max_send_message_size>
    <max_receive_message_size>-1</max_receive_message_size>
    <verbose_logs>false</verbose_logs>
  </grpc>
  {{- end }}
</clickhouse>
