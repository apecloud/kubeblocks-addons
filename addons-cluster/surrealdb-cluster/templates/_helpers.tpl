{{/*
Create the name of the service account to use
*/}}
{{- define "tidb-cluster.serviceAccountName" -}}
{{- default (printf "kb-%s" (include "clustername" .)) .Values.serviceAccount.name }}
{{- end }}

