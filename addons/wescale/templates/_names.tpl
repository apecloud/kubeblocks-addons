{{- define "apecloud-mysql.configConstraintVttabletName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mysql-scale-vttablet-config-constraints
{{- else -}}
{{- .Values.resourceNamePrefix -}}-vttablet-config-constraints
{{- end -}}
{{- end -}}

{{- define "apecloud-mysql.configConstraintVtgateName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mysql-scale-vtgate-config-constraints
{{- else -}}
{{- .Values.resourceNamePrefix -}}-vtgate-config-constraints
{{- end -}}
{{- end -}}

{{- define "apecloud-mysql.configTplVttabletName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
vttablet-config-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-vttablet-config-template
{{- end -}}
{{- end -}}

{{- define "apecloud-mysql.configTplVtgateName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
vtgate-config-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-vtgate-config-template
{{- end -}}
{{- end -}}
