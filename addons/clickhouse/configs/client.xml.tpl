<config>
  <user>admin</user>
  <password from_env="CLICKHOUSE_ADMIN_PASSWORD"/>
  {{- if eq $.TLS_ENABLED "true" -}}
  {{- $CA_FILE := /etc/pki/tls/ca.pem -}}
  {{- $CERT_FILE := /etc/pki/tls/cert.pem -}}
  {{- $KEY_FILE := /etc/pki/tls/key.pem }}
  <secure>true</secure>
  <openSSL>
    <client>
      <caConfig>{{$CA_FILE}}</caConfig>
    </client>
  </openSSL>
  {{- end }}
</config>
