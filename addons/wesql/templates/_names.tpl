{{/*
Define xtrabackup actionSet name
*/}}
{{- define "wesql.xtrabackupActionSetName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wesql-xtrabackup
{{- else -}}
{{- .Values.resourceNamePrefix -}}-xtrabackup
{{- end -}}
{{- end -}}

{{/*
Define volume snapshot actionSet name
*/}}
{{- define "wesql.vsActionSetName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wesql-volume-snapshot
{{- else -}}
{{- .Values.resourceNamePrefix -}}-volumesnapshot
{{- end -}}
{{- end -}}

{{/*
Define backup policy template
*/}}
{{- define "wesql.backupPolicyTemplateName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wesql-backup-policy-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-bpt
{{- end -}}
{{- end -}}

{{/*
Define cluster definition name, if resourceNamePrefix is specified, use it as clusterDefName
*/}}
{{- define "wesql.clusterDefName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wesql
{{- else -}}
{{- .Values.resourceNamePrefix -}}
{{- end -}}
{{- end -}}

{{/*
Define wesql-server component definition name prefix
*/}}
{{- define "wesql.cmpdNameWeSQLServerPrefix" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wesql-server-
{{- else -}}
{{- .Values.resourceNamePrefix -}}-wesql-server-
{{- end -}}
{{- end -}}

{{/*
{{- end -}}

{{/*
Define wescale component definition name prefix
*/}}
{{- define "wesql.cmpdNameWeScalePrefix" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wescale-
{{- else -}}
{{- .Values.resourceNamePrefix -}}-wescale-
{{- end -}}
{{- end -}}

{{/*
Define wescale controller component definition name prefix
*/}}
{{- define "wesql.cmpdNameWeScaleCtrlPrefix" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wescalecontroller-
{{- else -}}
{{- .Values.resourceNamePrefix -}}-wescale-controller-
{{- end -}}
{{- end -}}

{{/*
Define wesql-server component definition name
*/}}
{{- define "wesql.cmpdNameWeSQLServer" -}}
{{ include "wesql.cmpdNameWeSQLServerPrefix" . }}{{ .Chart.Version }}
{{- end -}}

{{/*
Define wescale component definition name
*/}}
{{- define "wesql.cmpdNameWeScale" -}}
{{ include "wesql.cmpdNameWeScalePrefix" . }}{{ .Chart.Version }}
{{- end -}}

{{/*
Define wescale-controller component definition name
*/}}
{{- define "wesql.cmpdNameWeScaleCtrl" -}}
{{ include "wesql.cmpdNameWeScaleCtrlPrefix" . }}{{ .Chart.Version }}
{{- end -}}

{{/*
Define config constriant name
*/}}
{{- define "wesql.configConstraintName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wesql-server-config-constraints
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-constraints
{{- end -}}
{{- end -}}

{{- define "wesql.configConstraintVttabletName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wescale-vttablet-config-constraints
{{- else -}}
{{- .Values.resourceNamePrefix -}}-vttablet-config-constraints
{{- end -}}
{{- end -}}

{{- define "wesql.configConstraintVtgateName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wescale-vtgate-config-constraints
{{- else -}}
{{- .Values.resourceNamePrefix -}}-vtgate-config-constraints
{{- end -}}
{{- end -}}

{{- define "wesql.configTplName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wesql-server-config-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-template
{{- end -}}
{{- end -}}

{{- define "wesql.configTplVttabletName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
vttablet-config-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-vttablet-config-template
{{- end -}}
{{- end -}}

{{- define "wesql.configTplVtgateName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
vtgate-config-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-vtgate-config-template
{{- end -}}
{{- end -}}

{{- define "wesql.cmReloadScriptName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wesql-server-reload-script
{{- else -}}
{{- .Values.resourceNamePrefix -}}-reload-script
{{- end -}}
{{- end -}}

{{- define "wesql.cmScriptsName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wesql-scripts
{{- else -}}
{{- .Values.resourceNamePrefix -}}-scripts
{{- end -}}
{{- end -}}
