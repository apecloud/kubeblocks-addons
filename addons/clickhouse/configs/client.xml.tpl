<config>
  <user from_env="CLICKHOUSE_ADMIN_USER"/>
  <password from_env="CLICKHOUSE_ADMIN_PASSWORD"/>
  {{- if eq (index $ "TLS_ENABLED") "true" -}}
  {{- $CA_FILE := "/etc/pki/tls/ca.pem" -}}
  {{- $CERT_FILE := "/etc/pki/tls/cert.pem" -}}
  {{- $KEY_FILE := "/etc/pki/tls/key.pem" }}
  <secure>true</secure>
  <port from_env="CLICKHOUSE_TCP_SECURE_PORT"/>
  <openSSL>
    <client>
      <caConfig>{{$CA_FILE}}</caConfig>
      <certificateFile>{{$CERT_FILE}}</certificateFile>
      <privateKeyFile>{{$KEY_FILE}}</privateKeyFile>
    </client>
  </openSSL>
  {{- end }}
</config>
