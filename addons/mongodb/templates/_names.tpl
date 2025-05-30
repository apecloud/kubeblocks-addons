{{/*
Define xtrabackup actionSet name
*/}}
{{- define "mongodb.xtrabackupActionSetName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
xtrabackup-for-mongodb
{{- else -}}
{{- .Values.resourceNamePrefix -}}-xtrabackup
{{- end -}}
{{- end -}}

{{/*
Define volume snapshot actionSet name
*/}}
{{- define "mongodb.vsActionSetName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
volumesnapshot-for-mongodb
{{- else -}}
{{- .Values.resourceNamePrefix -}}-volumesnapshot
{{- end -}}
{{- end -}}

{{/*
Define backup policy template
*/}}
{{- define "mongodb.backupPolicyTemplateName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongodb-backup-policy-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-bpt
{{- end -}}
{{- end -}}

{{/*
Define backup policy template
*/}}
{{- define "mongodb.hscaleBackupPolicyTemplateName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongodb-backup-policy-for-hscale
{{- else -}}
{{- .Values.resourceNamePrefix -}}-bpt-for-hscale
{{- end -}}
{{- end -}}

{{/*
Define cluster definition name, if resourceNamePrefix is specified, use it as clusterDefName
*/}}
{{- define "mongodb.clusterDefName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongodb
{{- else -}}
{{- .Values.resourceNamePrefix -}}
{{- end -}}
{{- end -}}

{{/*
Define component definition name
*/}}
{{- define "mongodb.componentDefName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongodb
{{- else -}}
{{- .Values.resourceNamePrefix -}}
{{- end -}}
{{- end -}}

{{/*
Define config constriant name
*/}}
{{- define "mongodb.configConstraintName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongodb-config-constraints
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-constraints
{{- end -}}
{{- end -}}

{{- define "mongodb.configTplName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongodb5.0-config-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-config-template
{{- end -}}
{{- end -}}

{{- define "mongodb.cmScriptsName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongodb-scripts
{{- else -}}
{{- .Values.resourceNamePrefix -}}-scripts
{{- end -}}
{{- end -}}

{{/*
Define parameter config renderername
*/}}
{{- define "mongodb.pcrName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongodb-pcr
{{- else -}}
{{- .Values.resourceNamePrefix -}}-pcr
{{- end -}}
{{- end -}}
