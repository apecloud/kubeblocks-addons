{{/*
Expand the name of the chart.
*/}}
{{- define "mssql.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "mssql.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "mssql.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mssql.labels" -}}
helm.sh/chart: {{ include "mssql.chart" . }}
{{ include "mssql.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mssql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mssql.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Product ID, if productKey is not empty, use productKey, otherwise use productEdition
*/}}
{{- define "mssql.productID" -}}
{{- if .Values.productKey }}
{{- .Values.productKey }}
{{- else }}
{{- .Values.productEdition }}
{{- end }}
{{- end }}

{{/*
Host network environment
*/}}
{{- define "mssql.host_network" -}}
{{- if .Values.hostNetworkEnabled -}}
enabled
{{- else -}}
disabled
{{- end -}}
{{- end -}}

{{/*
Generate pk password
*/}}
{{- define "mssql.generate_pk_password" -}}
{{- if not .Values.certificates.custom -}}
{{- include "mssql.generate_strong_password" . -}}
{{- end -}}
{{- end -}}


{{/*
Certificate secret name
*/}}
{{- define "mssql.certificate_secret_name" -}}
{{- if .Values.remoteSetting.isStandby -}}
{{- /* A standby cluster does not create its own certificate secret; it must
       reuse the primary cluster's dbm certificate secret. Fail fast at render
       time if it was not provided, instead of rendering an unresolvable,
       non-optional secretKeyRef that makes every pod die with
       CreateContainerConfigError and no hint about the missing value. */ -}}
{{- if not .Values.remoteSetting.primaryCertificateSecret.name -}}
{{- fail "remoteSetting.isStandby is true but remoteSetting.primaryCertificateSecret.name is empty: a standby cluster needs the primary cluster's dbm certificate secret (set remoteSetting.primaryCertificateSecret.name)" -}}
{{- end -}}
{{- .Values.remoteSetting.primaryCertificateSecret.name -}}
{{- else -}}
{{- include "kblib.clusterName" . }}-certificates
{{- end -}}
{{- end }}


{{/*
SQL Server 2019 uses a short machine account name for SQL Server Agent.
The generated pod hostname must stay within 15 characters, otherwise SQL
Agent startup can fail before database lifecycle SQL runs.
*/}}
{{- define "mssql.validate.sqlServer2019Hostname" -}}
{{- $version := toString .Values.version -}}
{{- if hasPrefix "2019" $version -}}
{{- $hostname := printf "%s-mssql-0" (include "kblib.clusterName" .) -}}
{{- if gt (len $hostname) 15 -}}
{{- fail (printf "SQL Server 2019 requires the generated Pod hostname to be no more than 15 characters for SQL Server Agent. Release/cluster name %q generates hostname %q (%d characters); use a release name of at most 7 characters or use SQL Server 2022+." .Release.Name $hostname (len $hostname)) -}}
{{- end -}}
{{- end -}}
{{- end -}}


{{/*
Component TLS stanza. ComponentDefinition owns the mount path and filenames.
*/}}
{{- define "mssql.tls" }}
{{- if .Values.tls.enabled }}
tls: true
issuer:
  name: {{ .Values.tls.issuer }}
{{- if eq .Values.tls.issuer "UserProvided" }}
{{- if not .Values.tls.secretName }}
{{- fail "tls.secretName is required when tls.issuer=UserProvided" }}
{{- end }}
  secretRef:
    name: {{ .Values.tls.secretName }}
    namespace: {{ .Release.Namespace }}
    ca: ca.crt
    cert: tls.crt
    key: tls.key
{{- end }}
{{- end }}
{{- end }}


{{/*
Generate strong password
*/}}
{{- define "mssql.generate_strong_password" -}}
{{- /* Generate components: uppercase, lowercase, digit, symbol */ -}}
{{- $upper := randAlpha 5 | upper -}}
{{- $lower := randAlpha 5 | lower -}}
{{- $digits := toString (randNumeric 2) -}}
{{- $symbols := list "!" "@" "#" "$" "%" "^" "&" "*" "(" ")" "-" "_" "=" "+" | join "" | shuffle | trunc 2 -}}
{{- /* Combine all components */ -}}
{{- $base := printf "%s%s%s%s" $upper $lower $digits $symbols | shuffle | join "" -}}
{{- /* Add padding to ensure minimum length */ -}}
{{- $padding := randAlphaNum (int (sub 16 (len $base))) -}}
{{- $password := printf "%s%s" $base $padding | shuffle | join "" -}}
{{- $password -}}
{{- end -}}


{{/*
Validate the defaultDBName value.
*/}}
{{- define "mssql.validate.defaultDBName" -}}
{{- if .Values.defaultDBName }}
{{- $dbNameRegex := "^[a-zA-Z@#_][a-zA-Z0-9@$#_]{0,127}$" -}}
{{- if not (mustRegexMatch $dbNameRegex .Values.defaultDBName) }}
{{- fail (printf "Invalid defaultDBName: %s. The database name must be 1-128 characters long, start with a letter, _, @, or #, and can only contain letters, numbers, and the symbols _, @, $, #." .Values.defaultDBName) }}
{{- end }}
{{- .Values.defaultDBName -}}
{{- else -}}
{{- print "db1" -}}
{{- end }}
{{- end -}}
