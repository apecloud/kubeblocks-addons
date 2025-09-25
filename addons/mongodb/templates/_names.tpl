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

{{- define "mongos.configTplName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongodb-mongos-config-template
{{- else -}}
{{- .Values.resourceNamePrefix -}}-mongodb-mongos-config-template
{{- end -}}
{{- end -}}

{{- define "mongodbShard.configTplName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongodb-shard-config-template
{{- else -}}
{{- printf "%s-mongodb-shard-config-template" .Values.resourceNamePrefix -}}
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
Define parametersDefinition name
*/}}
{{- define "mongod.paramsDefName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongod-paramsdef-{{ .Chart.Version }}
{{- else -}}
{{- .Values.resourceNamePrefix -}}-mongod-paramsdef
{{- end -}}
{{- end -}}

{{- define "mongos.paramsDefName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongos-paramsdef-{{ .Chart.Version }}
{{- else -}}
{{- .Values.resourceNamePrefix -}}-mongos-paramsdef
{{- end -}}
{{- end -}}

{{/*
Define parameter config renderername
*/}}
{{- define "mongodb.pcrName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongodb-pcr-{{ .Chart.Version }}
{{- else -}}
{{- .Values.resourceNamePrefix -}}-pcr
{{- end -}}
{{- end -}}

{{- define "mongoShard.pcrName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongo-shard-pcr-{{ .Chart.Version }}
{{- else -}}
{{- .Values.resourceNamePrefix -}}-shard-pcr
{{- end -}}
{{- end -}}

{{- define "cfgServer.pcrName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongo-config-server-pcr-{{ .Chart.Version }}
{{- else -}}
{{- .Values.resourceNamePrefix -}}-cfg-pcr
{{- end -}}
{{- end -}}

{{- define "mongos.pcrName" -}}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongo-mongos-pcr-{{ .Chart.Version }}
{{- else -}}
{{- .Values.resourceNamePrefix -}}-mongos-pcr
{{- end -}}
{{- end -}}

{{- define "mongodbShard.cmScriptsName" }}
{{- if eq (len .Values.resourceNamePrefix) 0 -}}
mongodb-shard-scripts
{{- else -}}
{{- .Values.resourceNamePrefix -}}-mongodb-shard-scripts
{{- end -}}
{{- end -}}