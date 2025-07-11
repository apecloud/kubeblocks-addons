# full example can be seen at:
# https://github.com/pingcap/tidb/blob/release-7.5/pkg/config/config.toml.example

[security]
{{- if eq (index $ "TLS_ENABLED") "true" }}
# Path of file that contains list of trusted SSL CAs for connection with mysql client.
ssl-ca = "/etc/pki/tls/ca.pem"

# Path of file that contains X509 certificate in PEM format for connection with mysql client.
ssl-cert = "/etc/pki/tls/cert.pem"

# Path of file that contains X509 key in PEM format for connection with mysql client.
ssl-key = "/etc/pki/tls/key.pem"
{{- end -}}

{{/* a dirty way to inject user defined config */}}
{{- $conponentTls := false }}
{{- $container := index $.podSpec.containers 0}}
{{- range $e := $container.env }}
{{- if and (eq $e.name "KB_ENABLE_TLS_BETWEEN_COMPONENTS") (eq $e.value "true") }}
{{- $conponentTls = true }}
{{- end }}
{{- end }}

{{- if eq $conponentTls true }}
# Path of file that contains list of trusted SSL CAs for connection with cluster components.
cluster-ssl-ca = "/etc/pki/cluster-tls/ca.pem"

# Path of file that contains X509 certificate in PEM format for connection with cluster components.
cluster-ssl-cert = "/etc/pki/cluster-tls/cert.pem"

# Path of file that contains X509 key in PEM format for connection with cluster components.
cluster-ssl-key = "/etc/pki/cluster-tls/key.pem"
{{- end }}
