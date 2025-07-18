<config>
  <user>admin</user>
  <password from_env="CLICKHOUSE_ADMIN_PASSWORD"/>
  {{- if $.component.tlsConfig -}}
  {{- $CA_FILE := getCAFile -}}
  <secure>true</secure>
  <openSSL>
    <client>
      <caConfig>{{$CA_FILE}}</caConfig>
    </client>
  </openSSL>
  {{- end }}
</config>