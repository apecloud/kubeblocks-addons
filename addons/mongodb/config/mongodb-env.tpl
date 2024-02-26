{{- $mongodb_port_info := getPortByName ( index $.podSpec.containers 0 ) "mongodb" }}

## for mongodb port
{{- $mongodb_port := 27017 }}
{{- if $mongodb_port_info }}
  {{- $mongodb_port = $mongodb_port_info.containerPort }}
{{- end }}
SERVICE_PORT: {{ $mongodb_port }}
