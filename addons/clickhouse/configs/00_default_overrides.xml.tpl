{{- $clusterName := $.cluster.metadata.name }}
{{- $namespace := $.cluster.metadata.namespace }}
<clickhouse>
  <listen_host>0.0.0.0</listen_host>
  {{- if $.component.tlsConfig }}
  <https_port replace="replace" from_env="CLICKHOUSE_HTTPS_PORT"/>
  <tcp_port_secure replace="replace" from_env="CLICKHOUSE_NATIVE_SECURE_PORT"/>
  <interserver_https_port replace="replace" from_env="CLICKHOUSE_INTERSERVER_HTTPS_PORT"/>
  <interserver_http_port remove="remove"/>
  {{- else }}
  <http_port replace="replace" from_env="CLICKHOUSE_HTTP_PORT"/>
  <tcp_port replace="replace" from_env="CLICKHOUSE_TCP_PORT"/>
  <interserver_http_port replace="replace" from_env="CLICKHOUSE_INTERSERVER_HTTP_PORT"/>
  <interserver_https_port remove="remove"/>
  {{- end }}
  <!-- Macros -->
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
      {{- range $.cluster.spec.componentSpecs }}
      {{- $compIter := . }}
      {{- if eq $compIter.componentDef "clickhouse" }}
      <shard>
        <!-- TODO if needed to add default user? -->
        {{- $replicas := $compIter.replicas | int }}
        {{- range $i, $_e := until $replicas }}
        <replica>
          <host>{{ $clusterName }}-{{ $compIter.name }}-{{ $i }}.{{ $clusterName }}-{{ $compIter.name }}-headless.{{ $namespace }}.svc.{{- $.clusterDomain }}</host>
          {{- if $.component.tlsConfig }}
          <port replace="replace" from_env="CLICKHOUSE_NATIVE_SECURE_PORT"/>
          <secure>1</secure>
          {{- else }}
          <port replace="replace" from_env="CLICKHOUSE_TCP_PORT"/>
          {{- end }}
        </replica>
        {{- end }}
      </shard>
      {{- end }}
      {{- end }}
    </default>
  </remote_servers>
  {{- range $.cluster.spec.componentSpecs }}
  {{- $compIter := . }}
  {{- if or (eq $compIter.componentDef "zookeeper") (eq $compIter.componentDef "clickhouse-keeper") }}
  <!-- Zookeeper configuration -->
  <zookeeper>
    {{- $replicas := $compIter.replicas | int }}
    {{- range $i, $_e := until $replicas }}
    <node>
      <host>{{ $clusterName }}-{{ $compIter.name }}-{{ $i }}.{{ $clusterName }}-{{ $compIter.name }}-headless.{{ $namespace }}.svc.{{- $.clusterDomain }}</host>
      {{- if $.component.tlsConfig }}
      {{- if eq $compIter.componentDef "clickhouse-keeper" }}
      <port replace="replace" from_env="CLICKHOUSE_KEEPER_TCP_TLS_PORT"/>
      {{- else }}
      <port replace="replace" from_env="ZOOKEEPER_TCP_TLS_PORT"/>
      {{- end }}
      <secure>1</secure>
      {{- else }}
      {{- if eq $compIter.componentDef "clickhouse-keeper" }}
      <port replace="replace" from_env="CLICKHOUSE_KEEPER_TCP_PORT"/>
      {{- else }}
      <port replace="replace" from_env="ZOOKEEPER_TCP_PORT"/>
      {{- end }}
      {{- end }}
    </node>
    {{- end }}
  </zookeeper>
  {{- end }}
  {{- end }}
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
  {{- end }}
</clickhouse>
