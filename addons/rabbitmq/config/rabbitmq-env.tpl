{{- $rabbitmq_port_info := getPortByName ( index $.podSpec.containers 0 ) "amqp" }}

## for rabbitmq port
{{- $rabbitmq_port := 5672 }}
{{- if $rabbitmq_port_info }}
  {{- $rabbitmq_port = $rabbitmq_port_info.containerPort }}
{{- end }}
SERVICE_PORT: {{ $rabbitmq_port }}
