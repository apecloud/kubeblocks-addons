[security]
{{- if eq (index $ "TLS_ENABLED") "true" }}

# Path of file that contains list of trusted SSL CAs for connection with mysql client.
ssl-ca = "/etc/pki/tls/ca.pem"

# Path of file that contains X509 certificate in PEM format for connection with mysql client.
ssl-cert = "/etc/pki/tls/cert.pem"

# Path of file that contains X509 key in PEM format for connection with mysql client.
ssl-key = "/etc/pki/tls/key.pem"

{{- end }}
