http-idle-timeout = "180s"
storage-compact-full-write-cold-duration = "240m"
{{- if eq (index . "TLS_ENABLED") "true" }}
tls-cert = "{{ .TLS_MOUNT_PATH }}/tls.crt"
tls-key = "{{ .TLS_MOUNT_PATH }}/tls.key"
{{- end }}
