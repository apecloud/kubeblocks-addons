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

{{- define "mysql.cmpdMGRNamePrefix" -}}
{{ include "mysql.cmpdNamePrefix" . }}-mgr
{{- end -}}

{{/*
Define mysql component definition regex regular
*/}}
{{- define "mysql.componentDefRegex" -}}
{{- printf "^%s" (include "mysql.cmpdNamePrefix" .) -}}-\d+\.\d+.*$
{{- end -}}

{{/*
Define mysql component definition common regex regular (semisync and orc)
*/}}
{{- define "mysql.componentDefCommonRegex" -}}
{{- printf "^%s" (include "mysql.cmpdNamePrefix" .) -}}(?:-[\w\d]+)?-\d+\.\d+.*$
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

{{- define "mysql.componentDefNameMGR80" -}}
{{- printf "%s-8.0-%s" (include "mysql.cmpdMGRNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "mysql.componentDefName84" -}}
{{- printf "%s-8.4-%s" (include "mysql.cmpdNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{- define "mysql.componentDefNameMGR84" -}}
{{- printf "%s-8.4-%s" (include "mysql.cmpdMGRNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{/*
Define mysql component definition name
*/}}
{{- define "proxysql.componentDefName" -}}
{{- printf "proxysql-%s-%s" (include "mysql.cmpdNamePrefix" .) .Chart.Version -}}
{{- end -}}

{{/*
Define parametersdefinition name
*/}}
{{- define "mysql.paramsDefName57" -}}
mysql-5.7-pd
{{- end -}}

{{/*
Define parametersdefinition name
*/}}
{{- define "mysql.paramsDefName80" -}}
mysql-8.0-pd
{{- end -}}


{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcName57" -}}
mysql-5.7-pcr
{{- end -}}

{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcNameOrc57" -}}
mysql-5.7-orc-pcr
{{- end -}}

{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcName80" -}}
mysql-8.0-pcr
{{- end -}}

{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcNameOrc80" -}}
mysql-8.0-orc-pcr
{{- end -}}

{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcNameMgr80" -}}
mysql-8.0-mgr-pcr
{{- end -}}

{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcNameMgr84" -}}
mysql-8.4-mgr-pcr
{{- end -}}


{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcName84" -}}
mysql-8.4-pcr
{{- end -}}
