# full example can be seen at:
# https://github.com/tikv/pd/blob/release-7.5/conf/config.toml

[security]
{{- if eq (index $ "KB_ENABLE_TLS_BETWEEN_COMPONENTS") "true" }}
# Path of file that contains list of trusted SSL CAs. if set, following four settings shouldn't be empty
cacert-path = "/etc/pki/cluster-tls/ca.pem"

# Path of file that contains X509 certificate in PEM format.
cert-path = "/etc/pki/cluster-tls/cert.pem"

# Path of file that contains X509 key in PEM format.
key-path = "/etc/pki/cluster-tls/key.pem"
{{- end -}}
