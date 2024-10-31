{{/*
Define xtrabackup actionSet name
*/}}
{{- define "apecloud-mysql.xtrabackupActionSetName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
xtrabackup-for-apecloud-mysql
{{- else -}}
{{- .Values.resourceNamePrefix -}}-xtrabackup
{{- end -}}
{{- end -}}

{{/*
Define volume snapshot actionSet name
*/}}
{{- define "apecloud-mysql.vsActionSetName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
volumesnapshot-for-apecloud-mysql
{{- else -}}
{{- .Values.resourceNamePrefix -}}-volumesnapshot
{{- end -}}
{{- end -}}

{{/*
Define backup policy template
*/}}
{{- define "apecloud-mysql.backupPolicyTemplateName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
apecloud-mysql-backup-policy-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-bpt
{{- end -}}
{{- end -}}

{{/*
Define backup policy template
*/}}
{{- define "apecloud-mysql.hscaleBackupPolicyTemplateName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
apecloud-mysql-backup-policy-for-hscale
{{- else -}}
{{- .Values.resourceNamePrefix -}}-bpt-for-hscale
{{- end -}}
{{- end -}}


{{/*
Define cluster definition name, if resourceNamePrefix is specified, use it as clusterDefName
*/}}
{{- define "apecloud-mysql.clusterDefName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
apecloud-mysql
{{- else -}}
{{- .Values.resourceNamePrefix -}}
{{- end -}}
{{- end -}}

{{/*
Define apecloud-mysql component definition name prefix
*/}}
{{- define "apecloud-mysql.cmpdNameApecloudMySQLPrefix" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
apecloud-mysql-
{{- else -}}
{{- .Values.resourceNamePrefix -}}-apecloud-mysql-
{{- end -}}
{{- end -}}

{{/*
{{- end -}}

{{/*
Define wescale component definition name prefix
*/}}
{{- define "apecloud-mysql.cmpdNameWescalePrefix" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wescale-
{{- else -}}
{{- .Values.resourceNamePrefix -}}-wescale-
{{- end -}}
{{- end -}}

{{/*
Define wescale controller component definition name prefix
*/}}
{{- define "apecloud-mysql.cmpdNameWescaleCtrlPrefix" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
wescale-controller-
{{- else -}}
{{- .Values.resourceNamePrefix -}}-wescale-controller-
{{- end -}}
{{- end -}}

{{/*
Define apecloud-mysql component definition name
*/}}
{{- define "apecloud-mysql.cmpdNameApecloudMySQL" -}}
{{ include "apecloud-mysql.cmpdNameApecloudMySQLPrefix" . }}{{ .Chart.Version }}
{{- end -}}

{{/*
Define wescale component definition name
*/}}
{{- define "apecloud-mysql.cmpdNameWescale" -}}
{{ include "apecloud-mysql.cmpdNameWescalePrefix" . }}{{ .Chart.Version }}
{{- end -}}

{{/*
Define wescale-controller component definition name
*/}}
{{- define "apecloud-mysql.cmpdNameWescaleCtrl" -}}
{{ include "apecloud-mysql.cmpdNameWescaleCtrlPrefix" . }}{{ .Chart.Version }}
{{- end -}}

{{/*
Define config constriant name
*/}}
{{- define "apecloud-mysql.configConstraintName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
apecloud-mysql8.0-config-constraints
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-constraints
{{- end -}}
{{- end -}}

{{- define "apecloud-mysql.configConstraintVttabletName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
apecloud-mysql-scale-vttablet-config-constraints
{{- else -}}
{{- .Values.resourceNamePrefix -}}-vttablet-config-constraints
{{- end -}}
{{- end -}}

{{- define "apecloud-mysql.configConstraintVtgateName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
apecloud-mysql-scale-vtgate-config-constraints
{{- else -}}
{{- .Values.resourceNamePrefix -}}-vtgate-config-constraints
{{- end -}}
{{- end -}}

{{- define "apecloud-mysql.configTplName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mysql8.0-config-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-template
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

{{- define "apecloud-mysql.cmReloadScriptName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mysql-reload-script
{{- else -}}
{{- .Values.resourceNamePrefix -}}-reload-script
{{- end -}}
{{- end -}}

{{- define "apecloud-mysql.cmScriptsName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
apecloud-mysql-scripts
{{- else -}}
{{- .Values.resourceNamePrefix -}}-scripts
{{- end -}}
{{- end -}}
