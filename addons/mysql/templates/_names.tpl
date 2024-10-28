{{/*
Define mysql component definition name prefix
*/}}
{{- define "mysql.cmpdNamePrefix" -}}
{{- default "mysql" .Values.cmpdNamePrefix -}}
{{- end -}}

{{/*
Define mysql orc component definition name prefix
*/}}
{{- define "mysql.cmpdOrcNamePrefix" -}}
{{ include "mysql.cmpdNamePrefix" . }}-orc
{{- end -}}

{{/*
Define mysql component definition regex regular
*/}}
{{- define "mysql.componentDefRegex" -}}
{{- printf "^%s" (include "mysql.cmpdNamePrefix" .) -}}-\d+\.\d+.*$
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefName57" -}}
{{- printf "%s-5.7-%s" (include "mysql.cmpdNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefNameOrc57" -}}
{{- printf "%s-5.7-%s" (include "mysql.cmpdOrcNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefName80" -}}
{{- printf "%s-8.0-%s" (include "mysql.cmpdNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefNameOrc80" -}}
{{- printf "%s-8.0-%s" (include "mysql.cmpdOrcNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefName84" -}}
{{- printf "%s-8.4-%s" (include "mysql.cmpdNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "proxysql.componentDefName" -}}
{{- printf "%s-proxysql-%s" (include "mysql.cmpdNamePrefix" .) .Chart.Version -}}
{{- end -}}
