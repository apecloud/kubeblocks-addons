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
Component definition patterns used by ComponentVersion.spec.compatibilityRules[].compDefs.
KubeBlocks matches them with component.PrefixOrRegexMatched, which tries
strings.HasPrefix first, so a plain name prefix is enough (no regex metacharacters,
no chart version). Each pattern is derived from the corresponding ComponentDefinition
name helper with the trailing chart version stripped, so the prefix can never drift
from cmpNamePrefix / Chart.Version changes.
*/}}

{{- define "mysql.componentDefPrefix57" -}}
{{- include "mysql.componentDefName57" . | trimSuffix (printf "-%s" .Chart.Version) -}}
{{- end -}}

{{- define "mysql.componentDefPrefix80" -}}
{{- include "mysql.componentDefName80" . | trimSuffix (printf "-%s" .Chart.Version) -}}
{{- end -}}

{{- define "mysql.componentDefPrefix84" -}}
{{- include "mysql.componentDefName84" . | trimSuffix (printf "-%s" .Chart.Version) -}}
{{- end -}}

{{- define "mysql.componentDefPrefixOrc57" -}}
{{- include "mysql.componentDefNameOrc57" . | trimSuffix (printf "-%s" .Chart.Version) -}}
{{- end -}}

{{- define "mysql.componentDefPrefixOrc80" -}}
{{- include "mysql.componentDefNameOrc80" . | trimSuffix (printf "-%s" .Chart.Version) -}}
{{- end -}}

{{- define "mysql.componentDefPrefixMGR80" -}}
{{- include "mysql.componentDefNameMGR80" . | trimSuffix (printf "-%s" .Chart.Version) -}}
{{- end -}}

{{- define "mysql.componentDefPrefixMGR84" -}}
{{- include "mysql.componentDefNameMGR84" . | trimSuffix (printf "-%s" .Chart.Version) -}}
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
Define parametersdefinition name
*/}}
{{- define "mysql.paramsDefName84" -}}
mysql-8.4-pd
{{- end -}}


{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcName57" -}}
mysql-5.7-pcr-{{ .Chart.Version }}
{{- end -}}

{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcNameOrc57" -}}
mysql-5.7-orc-pcr-{{ .Chart.Version }}
{{- end -}}

{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcName80" -}}
mysql-8.0-pcr-{{ .Chart.Version }}
{{- end -}}

{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcNameOrc80" -}}
mysql-8.0-orc-pcr-{{ .Chart.Version }}
{{- end -}}

{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcNameMgr80" -}}
mysql-8.0-mgr-pcr-{{ .Chart.Version }}
{{- end -}}

{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcNameMgr84" -}}
mysql-8.4-mgr-pcr-{{ .Chart.Version }}
{{- end -}}


{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysql.prcName84" -}}
mysql-8.4-pcr-{{ .Chart.Version }}
{{- end -}}

{{/*
Define parameterconfigrenderer name
*/}}
{{- define "mysqlProxy.prcName" -}}
mysql-proxy-pcr-{{ .Chart.Version }}
{{- end -}}

