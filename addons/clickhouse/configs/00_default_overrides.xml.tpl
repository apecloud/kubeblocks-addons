<clickhouse>
  <listen_host>0.0.0.0</listen_host>
  {{- if eq (index $ "TLS_ENABLED") "true" }}
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
    <shard from_env="CURRENT_SHARD_COMPONENT_SHORT_NAME"/>
    <replica from_env="CURRENT_POD_NAME"/>
    <layer>{{ .KB_CLUSTER_NAME }}</layer>
  </macros>
  <default_replica_path>/clickhouse/tables/{layer}/{shard}/{database}/{table}</default_replica_path>
  <default_replica_name>{replica}</default_replica_name>
  <!-- Log Level -->
  <logger>
    <level>information</level>
    <log>/bitnami/clickhouse/log/clickhouse-server.log</log>
    <errorlog>/bitnami/clickhouse/log/clickhouse-server.err.log</errorlog>
    <size>1000M</size>
    <count>3</count>
  </logger>
  <!-- Cluster configuration - Any update of the shards and replicas requires helm upgrade -->
  <remote_servers>
    <{{ .INIT_CLUSTER_NAME }}>
      {{- range $key, $value := . }}
      {{- if and (hasPrefix "ALL_SHARDS_POD_FQDN_LIST" $key) (ne $value "") }}
      <shard>
        <internal_replication>true</internal_replication>
        {{- range $_, $host := splitList "," $value }}
        <replica>
          <host>{{ $host }}</host>
          {{- if eq (index $ "TLS_ENABLED") "true" }}
          <port replace="replace" from_env="CLICKHOUSE_TCP_SECURE_PORT"/>
          <secure>1</secure>
          {{- else }}
          <port replace="replace" from_env="CLICKHOUSE_TCP_PORT"/>
          {{- end }}
          <user from_env="CLICKHOUSE_ADMIN_USER"></user>
          <password from_env="CLICKHOUSE_ADMIN_PASSWORD"></password>
        </replica>
        {{- end }}
      </shard>
      {{- end }}
      {{- end }}
    </{{ .INIT_CLUSTER_NAME }}>
  </remote_servers>
  {{- if (index . "CH_KEEPER_POD_FQDN_LIST") }}
  <!-- Zookeeper configuration -->
  <zookeeper>
    {{- range $_, $host := splitList "," .CH_KEEPER_POD_FQDN_LIST }}
    <node>
      <host>{{ $host }}</host>
      {{- if eq (index $ "TLS_ENABLED") "true" }}
      <port replace="replace" from_env="CLICKHOUSE_KEEPER_TCP_TLS_PORT"/>
      <secure>1</secure>
      {{- else }}
      <port replace="replace" from_env="CLICKHOUSE_KEEPER_TCP_PORT"/>
      {{- end }}
    </node>
    {{- end }}
  </zookeeper>
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
  {{- if eq (index $ "TLS_ENABLED") "true" -}}
  {{- $CA_FILE := "/etc/pki/tls/ca.pem" -}}
  {{- $CERT_FILE := "/etc/pki/tls/cert.pem" -}}
  {{- $KEY_FILE := "/etc/pki/tls/key.pem" }}
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
  <query_log>
    <database>system</database>
    <table>query_log</table>
    <partition_by>event_date</partition_by>
    <order_by>event_time</order_by>
    <ttl>event_date + INTERVAL 7 day</ttl>
    <flush_interval_milliseconds>7500</flush_interval_milliseconds>
    <max_size_rows>1048576</max_size_rows>
    <reserved_size_rows>8192</reserved_size_rows>
    <buffer_size_rows_flush_threshold>524288</buffer_size_rows_flush_threshold>
    <flush_on_crash>false</flush_on_crash>
  </query_log>
  <!-- User directories configuration -->
  <!-- see https://github.com/ClickHouse/ClickHouse/issues/78830 -->
  <user_directories replace="replace">
    <users_xml>
      <!-- Local static user directory (local path) -->
      <path>/bitnami/clickhouse/etc/users.d/default/user.xml</path>
    </users_xml>
    {{- if (index . "CH_KEEPER_POD_FQDN_LIST") }}
    <replicated>
      <!-- Keeper-based replicated user directory (keeper path) -->
      <zookeeper_path>/clickhouse/access</zookeeper_path>
    </replicated>
    {{- end }}
    <local_directory>
      <!-- Local dynamic user directory (local path, for standalone mode) -->
      <path>/bitnami/clickhouse/data/access/</path>
    </local_directory>
  </user_directories>
</clickhouse>
