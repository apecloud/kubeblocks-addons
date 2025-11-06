{{/*
Expand the name of the chart.
*/}}

{{/*
Define the cluster name.
We truncate at 15 chars because KubeBlocks will concatenate the names of other resources with cluster name
*/}}
{{- define "polardbx-cluster.name" -}}
{{- $name := default  .Release.Name .Values.clusterName }}
{{- if not (regexMatch "^[a-z]([-a-z0-9]*[a-z0-9])?$" $name) }}
{{ fail (printf "Release name %q is invalid. It must match the regex %q." $name "^[a-z]([-a-z0-9]*[a-z0-9])?$") }}
{{- end }}
{{- if gt (len $name) 16 }}
{{ fail (printf "Release name %q is invalid, must be no more than 6 characters" $name) }}
{{- end }}
{{- if gt (add (len $name) (len .Release.Namespace)) 18 }}
{{ fail (printf "Combined length of release name %q and namespace %q must be no more than 18 characters" $name .Release.Namespace) }}
{{- end }}
{{- $name }}
{{- end }}
