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
Define class name
*/}}
{{- define "apecloud-mysql.className" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
kb.classes.default.apecloud-mysql.mysql
{{- else -}}
{{- .Values.resourceNamePrefix -}}-class
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
Define cluster version
*/}}
{{- define "apecloud-mysql.clusterVersion" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
ac-mysql-{{ default .Chart.AppVersion .Values.clusterVersionOverride }}
{{- else -}}
{{- .Values.resourceNamePrefix -}}-{{ default .Chart.AppVersion .Values.clusterVersionOverride }}
{{- end -}}
{{- end -}}

{{/*
Define cluster version with auditlog
*/}}
{{- define "apecloud-mysql.clusterVersionAuditLog" -}}
{{- include "apecloud-mysql.clusterVersion" . }}-{{ default "1" .Values.auditlogSubVersion }}
{{- end -}}

{{/*
Define component defintion name
*/}}
{{- define "apecloud-mysql.componentDefName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
apecloud-mysql
{{- else -}}
{{- .Values.resourceNamePrefix -}}
{{- end -}}
{{- end -}}

{{/*
Define config constriant name
*/}}
{{- define "apecloud-mysql.configConstraintName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mysql8.0-config-constraints
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-constraints
{{- end -}}
{{- end -}}

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

{{- define "apecloud-mysql.configTplName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mysql8.0-config-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-template
{{- end -}}
{{- end -}}

{{- define "apecloud-mysql.configTplAuditLogName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mysql8.0-auditlog-config-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-auditlog-config-template
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