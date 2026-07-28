{{- define "mariadb-cluster.replicas" }}
{{- if eq .Values.mode "standalone" }}
{{- 1 }}
{{- else -}}
{{- .Values.replicas -}}
{{- end -}}
{{- end -}}

{{- define "mariadb-cluster.validateTopology" -}}
{{- $mode := .Values.mode -}}
{{- $replicas := int .Values.replicas -}}
{{- if and (eq $mode "replication") (lt $replicas 2) -}}
{{- fail "replication mode requires replicas >= 2" -}}
{{- end -}}
{{- if and (eq $mode "replication") (gt $replicas 5) -}}
{{- fail "replication mode requires replicas between 2 and 5" -}}
{{- end -}}
{{- if and (eq $mode "galera") (not (or (eq $replicas 3) (eq $replicas 5))) -}}
{{- fail "galera mode requires replicas to be one of 3 or 5" -}}
{{- end -}}
{{- end -}}
