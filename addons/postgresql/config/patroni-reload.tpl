{{- $restartParams := $.Files.Get "bootstrap.yaml" | fromYamlArray }}
{{- $patroniParamsContent := $.Files.Get "patroni_parameter.yaml" }}
{{- $patroniParams := fromYamlArray (default "" $patroniParamsContent) }}
{{- $command := "reload" }}
{{- $postgresql := dict }}
{{- $patroni := dict }}
{{- range $pk, $val := $.arg0 }}
    {{- if has $pk $patroniParams }}
        {{- set $patroni $pk ($val | trimAll "'") }}
    {{- else }}
        {{- /* trim single quotes for value in the pg config file */}}
        {{- set $postgresql $pk ($val | trimAll "'") }}
    {{- end }}
    {{- if has $pk $restartParams  }}
        {{- $command = "restart" }}
    {{- end }}
{{- end }}

{{- $params := merge $patroni (dict "postgresql" (dict "parameters" $postgresql)) }}
{{- $err := execSql (toJson $params) "config" }}
{{- if $err }}
    {{- failed $err }}
{{- end }}
{{- $err := execSql "" $command }}
{{- if $err }}
    {{- failed $err }}
{{- end }}
