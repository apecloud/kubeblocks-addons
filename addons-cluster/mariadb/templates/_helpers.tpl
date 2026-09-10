{{- define "mariadb-cluster.replicas" }}
{{- if eq .Values.mode "standalone" }}
{{- 1 }}
{{- else -}}
{{- .Values.replicas -}}
{{- end -}}
{{- end -}}

{{- define "mariadb-cluster.validateTopology" -}}
{{- $mode := .Values.mode -}}
{{- if not (or (eq $mode "standalone") (eq $mode "replication") (eq $mode "galera")) -}}
{{- fail "mode must be one of standalone, replication, or galera" -}}
{{- end -}}
{{- if not (or (kindIs "int64" .Values.replicas) (kindIs "float64" .Values.replicas)) -}}
{{- fail "replicas must be an integer between 1 and 5" -}}
{{- end -}}
{{- $replicasText := printf "%v" .Values.replicas -}}
{{- if not (regexMatch "^[0-9]+$" $replicasText) -}}
{{- fail "replicas must be an integer between 1 and 5" -}}
{{- end -}}
{{- $replicas := int .Values.replicas -}}
{{- if or (lt $replicas 1) (gt $replicas 5) -}}
{{- fail "replicas must be an integer between 1 and 5" -}}
{{- end -}}
{{- if and (eq $mode "replication") (lt $replicas 2) -}}
{{- fail "replication mode requires replicas >= 2" -}}
{{- end -}}
{{- if and (eq $mode "galera") (not (or (eq $replicas 3) (eq $replicas 5))) -}}
{{- fail "galera mode requires replicas to be one of 3 or 5" -}}
{{- end -}}
{{- end -}}
