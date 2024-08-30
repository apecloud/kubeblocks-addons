{{/*
Expand the name of the chart.
*/}}
{{- define "loki-cluster.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "loki-cluster.fullname" -}}
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
{{- define "loki-cluster.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "loki-cluster.labels" -}}
helm.sh/chart: {{ include "loki-cluster.chart" . }}
{{ include "loki-cluster.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "loki-cluster.selectorLabels" -}}
app.kubernetes.io/name: {{ include "loki-cluster.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "loki-cluster.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "loki-cluster.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "clustername" -}}
{{ include "loki-cluster.fullname" .}}
{{- end}}



{{/* Create a default storage config that uses filesystem storage
This is required for CI, but Loki will not be queryable with this default
applied, thus it is encouraged that users override this.
*/}}
{{- define "loki-cluster.storageConfig" -}}
{{- if .Values.loki.storageConfig -}}
{{- .Values.loki.storageConfig | toYaml | nindent 4 -}}
{{- else }}
{{- .Values.loki.defaultStorageConfig | toYaml | nindent 4 }}
{{- end}}
{{- end}}


{{/*
Base template for building docker image reference
*/}}
{{- define "loki-cluster.baseImage" }}
{{- $registry := .global.registry | default .service.registry -}}
{{- $repository := .service.repository -}}
{{- $tag := .service.tag | default .defaultVersion | toString -}}
{{- printf "%s/%s:%s" $registry $repository $tag -}}
{{- end -}}


{{/*
Generated storage config for loki-cluster common config
*/}}
{{- define "loki-cluster.commonStorageConfig" -}}
{{- if .Values.minio.enabled -}}
s3:
  endpoint: {{ include "loki-cluster.minio" $ }}
  bucketnames: {{ $.Values.loki.storage.bucketNames.chunks }}
  secret_access_key: supersecret
  access_key_id: enterprise-logs
  s3forcepathstyle: true
  insecure: true
{{- else if eq .Values.loki.storage.type "s3" -}}
{{- with .Values.loki.storage.s3 }}
s3:
  {{- with .s3 }}
  s3: {{ . }}
  {{- end }}
  {{- with .endpoint }}
  endpoint: {{ . }}
  {{- end }}
  {{- with .region }}
  region: {{ . }}
  {{- end}}
  bucketnames: {{ $.Values.loki.storage.bucketNames.chunks }}
  {{- with .secretAccessKey }}
  secret_access_key: {{ . }}
  {{- end }}
  {{- with .accessKeyId }}
  access_key_id: {{ . }}
  {{- end }}
  s3forcepathstyle: {{ .s3ForcePathStyle }}
  insecure: {{ .insecure }}
{{- end -}}
{{- else if eq .Values.loki.storage.type "gcs" -}}
{{- with .Values.loki.storage.gcs }}
gcs:
  bucket_name: {{ $.Values.loki.storage.bucketNames.chunks }}
  chunk_buffer_size: {{ .chunkBufferSize }}
  request_timeout: {{ .requestTimeout }}
  enable_http2: {{ .enableHttp2}}
{{- end -}}
{{- else -}}
{{- with .Values.loki.storage.local }}
filesystem:
  chunks_directory: {{ .chunks_directory }}
  rules_directory: {{ .rules_directory }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Storage config for ruler
*/}}
{{- define "loki-cluster.rulerStorageConfig" -}}
{{- if or .Values.minio.enabled (eq .Values.loki.storage.type "s3") -}}
s3:
  bucketnames: {{ $.Values.loki.storage.bucketNames.ruler }}
{{- else if eq .Values.loki.storage.type "gcs" -}}
gcs:
  bucket_name: {{ $.Values.loki.storage.bucketNames.ruler }}
{{- end -}}
{{- end -}}

{{/*
Memcached Docker image
*/}}
{{- define "loki.memcachedImage" -}}
{{- $dict := dict "service" .Values.memcached.image "global" .Values.global.image -}}
{{- include "loki-cluster.image" $dict -}}
{{- end }}

{{/*
Memcached Exporter Docker image
*/}}
{{- define "loki-cluster.memcachedExporterImage" -}}
{{- $dict := dict "service" .Values.memcachedExporter.image "global" .Values.global.image -}}
{{- include "loki-cluster.image" $dict -}}
{{- end }}

{{/*
Return the appropriate apiVersion for ingress.
*/}}
{{- define "loki-cluster.ingress.apiVersion" -}}
  {{- if and (.Capabilities.APIVersions.Has "networking.k8s.io/v1") (semverCompare ">= 1.19-0" .Capabilities.KubeVersion.Version) -}}
      {{- print "networking.k8s.io/v1" -}}
  {{- else if .Capabilities.APIVersions.Has "networking.k8s.io/v1beta1" -}}
    {{- print "networking.k8s.io/v1beta1" -}}
  {{- else -}}
    {{- print "extensions/v1beta1" -}}
  {{- end -}}
{{- end -}}

{{/*
Return if ingress is stable.
*/}}
{{- define "loki-cluster.ingress.isStable" -}}
  {{- eq (include "loki-cluster.ingress.apiVersion" .) "networking.k8s.io/v1" -}}
{{- end -}}

{{/*
Return if ingress supports ingressClassName.
*/}}
{{- define "loki-cluster.ingress.supportsIngressClassName" -}}
  {{- or (eq (include "loki-cluster.ingress.isStable" .) "true") (and (eq (include "loki-cluster.ingress.apiVersion" .) "networking.k8s.io/v1beta1") (semverCompare ">= 1.18-0" .Capabilities.KubeVersion.Version)) -}}
{{- end -}}

{{/*
Return if ingress supports pathType.
*/}}
{{- define "loki-cluster.ingress.supportsPathType" -}}
  {{- or (eq (include "loki-cluster.ingress.isStable" .) "true") (and (eq (include "loki-cluster.ingress.apiVersion" .) "networking.k8s.io/v1beta1") (semverCompare ">= 1.18-0" .Capabilities.KubeVersion.Version)) -}}
{{- end -}}

{{/*
Create the service endpoint including port for MinIO.
*/}}
{{- define "loki-cluster.minio" -}}
{{- if .Values.minio.enabled -}}
{{- printf "%s-%s.%s.svc:%s" .Release.Name "minio" .Release.Namespace (.Values.minio.service.port | toString) -}}
{{- end -}}
{{- end -}}

{{/* Return the appropriate apiVersion for PodDisruptionBudget. */}}
{{- define "loki-cluster.podDisruptionBudget.apiVersion" -}}
  {{- if and (.Capabilities.APIVersions.Has "policy/v1") (semverCompare ">= 1.21-0" .Capabilities.KubeVersion.Version) -}}
    {{- print "policy/v1" -}}
  {{- else -}}
    {{- print "policy/v1beta1" -}}
  {{- end -}}
{{- end -}}

{{/* Snippet for the nginx file used by gateway */}}
{{- define "loki-cluster.nginxFile" }}
worker_processes  5;  ## Default: 1
error_log  /dev/stderr;
pid        /tmp/nginx.pid;
worker_rlimit_nofile 8192;

events {
  worker_connections  4096;  ## Default: 1024
}

http {
  client_body_temp_path /tmp/client_temp;
  proxy_temp_path       /tmp/proxy_temp_path;
  fastcgi_temp_path     /tmp/fastcgi_temp;
  uwsgi_temp_path       /tmp/uwsgi_temp;
  scgi_temp_path        /tmp/scgi_temp;

  client_max_body_size  4M;

  proxy_read_timeout    600; ## 10 minutes
  proxy_send_timeout    600;
  proxy_connect_timeout 600;

  proxy_http_version    1.1;

  default_type application/octet-stream;
  log_format   {{ .Values.gateway.nginxConfig.logFormat }}

  {{- if .Values.gateway.verboseLogging }}
  access_log   /dev/stderr  main;
  {{- else }}

  map $status $loggable {
    ~^[23]  0;
    default 1;
  }
  access_log   /dev/stderr  main  if=$loggable;
  {{- end }}

  sendfile     on;
  tcp_nopush   on;
  {{- if .Values.gateway.nginxConfig.resolver }}
  resolver {{ .Values.gateway.nginxConfig.resolver }};
  {{- else }}
  resolver {{ .Values.global.dnsService }}.{{ .Values.global.dnsNamespace }}.svc.{{ .Values.global.clusterDomain }}.;
  {{- end }}

  {{- with .Values.gateway.nginxConfig.httpSnippet }}
  {{- tpl . $ | nindent 2 }}
  {{- end }}

  server {
    {{- if (.Values.gateway.nginxConfig.ssl) }}
    listen             8080 ssl;
    {{- if .Values.gateway.nginxConfig.enableIPv6 }}
    listen             [::]:8080 ssl;
    {{- end }}
    {{- else }}
    listen             8080;
    {{- if .Values.gateway.nginxConfig.enableIPv6 }}
    listen             [::]:8080;
    {{- end }}
    {{- end }}

    {{- if .Values.gateway.basicAuth.enabled }}
    auth_basic           "Loki";
    auth_basic_user_file /etc/nginx/secrets/.htpasswd;
    {{- end }}

    location = / {
      return 200 'OK';
      auth_basic off;
    }

    ########################################################
    # Configure backend targets

    {{- $backendHost := include "loki-cluster.backendFullname" .}}
    {{- $readHost := include "loki-cluster.readFullname" .}}
    {{- $writeHost := include "loki-cluster.writeFullname" .}}

    {{- if .Values.read.legacyReadTarget }}
    {{- $backendHost = include "loki-cluster.readFullname" . }}
    {{- end }}

    {{- $httpSchema := .Values.gateway.nginxConfig.schema }}

    {{- $writeUrl    := printf "%s://%s.%s.svc.%s:%s" $httpSchema $writeHost   .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $readUrl     := printf "%s://%s.%s.svc.%s:%s" $httpSchema $readHost    .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $backendUrl  := printf "%s://%s.%s.svc.%s:%s" $httpSchema $backendHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}

    {{- if .Values.gateway.nginxConfig.customWriteUrl }}
    {{- $writeUrl  = .Values.gateway.nginxConfig.customWriteUrl }}
    {{- end }}
    {{- if .Values.gateway.nginxConfig.customReadUrl }}
    {{- $readUrl = .Values.gateway.nginxConfig.customReadUrl }}
    {{- end }}
    {{- if .Values.gateway.nginxConfig.customBackendUrl }}
    {{- $backendUrl = .Values.gateway.nginxConfig.customBackendUrl }}
    {{- end }}

    {{- $singleBinaryHost := include "loki-cluster.singleBinaryFullname" . }}
    {{- $singleBinaryUrl  := printf "%s://%s.%s.svc.%s:%s" $httpSchema $singleBinaryHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}

    {{- $distributorHost := include "loki-cluster.distributorFullname" .}}
    {{- $ingesterHost := include "loki-cluster.ingesterFullname" .}}
    {{- $queryFrontendHost := include "loki-cluster.queryFrontendFullname" .}}
    {{- $indexGatewayHost := include "loki-cluster.indexGatewayFullname" .}}
    {{- $rulerHost := include "loki-cluster.rulerFullname" .}}
    {{- $compactorHost := include "loki-cluster.compactorFullname" .}}
    {{- $schedulerHost := include "loki-cluster.querySchedulerFullname" .}}


    {{- $distributorUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $distributorHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) -}}
    {{- $ingesterUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $ingesterHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $queryFrontendUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $queryFrontendHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $indexGatewayUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $indexGatewayHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $rulerUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $rulerHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $compactorUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $compactorHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}
    {{- $schedulerUrl := printf "%s://%s.%s.svc.%s:%s" $httpSchema $schedulerHost .Release.Namespace .Values.global.clusterDomain (.Values.loki.server.http_listen_port | toString) }}

    {{- if eq (include "loki-cluster.deployment.isSingleBinary" .) "true"}}
    {{- $distributorUrl = $singleBinaryUrl }}
    {{- $ingesterUrl = $singleBinaryUrl }}
    {{- $queryFrontendUrl = $singleBinaryUrl }}
    {{- $indexGatewayUrl = $singleBinaryUrl }}
    {{- $rulerUrl = $singleBinaryUrl }}
    {{- $compactorUrl = $singleBinaryUrl }}
    {{- $schedulerUrl = $singleBinaryUrl }}
    {{- else if eq (include "loki-cluster.deployment.isScalable" .) "true"}}
    {{- $distributorUrl = $writeUrl }}
    {{- $ingesterUrl = $writeUrl }}
    {{- $queryFrontendUrl = $readUrl }}
    {{- $indexGatewayUrl = $backendUrl }}
    {{- $rulerUrl = $backendUrl }}
    {{- $compactorUrl = $backendUrl }}
    {{- $schedulerUrl = $backendUrl }}
    {{- end -}}

    # Distributor
    location = /api/prom/push {
      proxy_pass       {{ $distributorUrl }}$request_uri;
    }
    location = /loki-cluster/api/v1/push {
      proxy_pass       {{ $distributorUrl }}$request_uri;
    }
    location = /distributor/ring {
      proxy_pass       {{ $distributorUrl }}$request_uri;
    }
    location = /otlp/v1/logs {
      proxy_pass       {{ $distributorUrl }}$request_uri;
    }

    # Ingester
    location = /flush {
      proxy_pass       {{ $ingesterUrl }}$request_uri;
    }
    location ^~ /ingester/ {
      proxy_pass       {{ $ingesterUrl }}$request_uri;
    }
    location = /ingester {
      internal;        # to suppress 301
    }

    # Ring
    location = /ring {
      proxy_pass       {{ $ingesterUrl }}$request_uri;
    }

    # MemberListKV
    location = /memberlist {
      proxy_pass       {{ $ingesterUrl }}$request_uri;
    }

    # Ruler
    location = /ruler/ring {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }
    location = /api/prom/rules {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }
    location ^~ /api/prom/rules/ {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }
    location = /loki-cluster/api/v1/rules {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }
    location ^~ /loki-cluster/api/v1/rules/ {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }
    location = /prometheus/api/v1/alerts {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }
    location = /prometheus/api/v1/rules {
      proxy_pass       {{ $rulerUrl }}$request_uri;
    }

    # Compactor
    location = /compactor/ring {
      proxy_pass       {{ $compactorUrl }}$request_uri;
    }
    location = /loki-cluster/api/v1/delete {
      proxy_pass       {{ $compactorUrl }}$request_uri;
    }
    location = /loki-cluster/api/v1/cache/generation_numbers {
      proxy_pass       {{ $compactorUrl }}$request_uri;
    }

    # IndexGateway
    location = /indexgateway/ring {
      proxy_pass       {{ $indexGatewayUrl }}$request_uri;
    }

    # QueryScheduler
    location = /scheduler/ring {
      proxy_pass       {{ $schedulerUrl }}$request_uri;
    }

    # Config
    location = /config {
      proxy_pass       {{ $ingesterUrl }}$request_uri;
    }

    {{- if and .Values.enterprise.enabled .Values.enterprise.adminApi.enabled }}
    # Admin API
    location ^~ /admin/api/ {
      proxy_pass       {{ $backendUrl }}$request_uri;
    }
    location = /admin/api {
      internal;        # to suppress 301
    }
    {{- end }}


    # QueryFrontend, Querier
    location = /api/prom/tail {
      proxy_pass       {{ $queryFrontendUrl }}$request_uri;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
    }
    location = /loki-cluster/api/v1/tail {
      proxy_pass       {{ $queryFrontendUrl }}$request_uri;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
    }
    location ^~ /api/prom/ {
      proxy_pass       {{ $queryFrontendUrl }}$request_uri;
    }
    location = /api/prom {
      internal;        # to suppress 301
    }
    location ^~ /loki-cluster/api/v1/ {
      proxy_pass       {{ $queryFrontendUrl }}$request_uri;
    }
    location = /loki-cluster/api/v1 {
      internal;        # to suppress 301
    }

    {{- with .Values.gateway.nginxConfig.serverSnippet }}
    {{ . | nindent 4 }}
    {{- end }}
  }
}
{{- end }}

{{/*
singleBinary fullname
*/}}
{{- define "loki-cluster.singleBinaryFullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
write fullname
*/}}
{{- define "loki-cluster.writeFullname" -}}
{{ include "loki-cluster.name" . }}-write
{{- end }}

{{/*
read fullname
*/}}
{{- define "loki-cluster.readFullname" -}}
{{ include "loki-cluster.name" . }}-read
{{- end }}

{{/*
backend fullname
*/}}
{{- define "loki-cluster.backendFullname" -}}
{{ include "loki-cluster.name" . }}-backend
{{- end }}

{{/*
gateway fullname
*/}}
{{- define "loki-cluster.gatewayFullname" -}}
{{ include "loki-cluster.fullname" . }}-gateway
{{- end }}


{{/*
gateway selector labels
*/}}
{{- define "loki-cluster.gatewaySelectorLabels" -}}
{{ include "loki-cluster.selectorLabels" . }}
app.kubernetes.io/component: gateway
{{- end }}

{{/*
gateway auth secret name
*/}}
{{- define "loki-cluster.gatewayAuthSecret" -}}
{{ .Values.gateway.basicAuth.existingSecret | default (include "loki-cluster.gatewayFullname" . ) }}
{{- end }}

{{/*
gateway Docker image
*/}}
{{- define "loki-cluster.gatewayImage" -}}
{{- $dict := dict "service" .Values.gateway.image "global" .Values.global.image -}}
{{- include "loki-cluster.baseImage" $dict -}}
{{- end }}

{{/*
gateway priority class name
*/}}
{{- define "loki-cluster.gatewayPriorityClassName" -}}
{{- $pcn := coalesce .Values.global.priorityClassName .Values.gateway.priorityClassName -}}
{{- if $pcn }}
priorityClassName: {{ $pcn }}
{{- end }}
{{- end }}

{{/*
distributor fullname
*/}}
{{- define "loki-cluster.distributorFullname" -}}
{{ include "loki-cluster.fullname" . }}-distributor
{{- end }}

{{/*
ingester fullname
*/}}
{{- define "loki-cluster.ingesterFullname" -}}
{{ include "loki-cluster.fullname" . }}-ingester
{{- end }}

{{/*
query-frontend fullname
*/}}
{{- define "loki-cluster.queryFrontendFullname" -}}
{{ include "loki-cluster.fullname" . }}-query-frontend
{{- end }}

{{/*
index-gateway fullname
*/}}
{{- define "loki-cluster.indexGatewayFullname" -}}
{{ include "loki-cluster.fullname" . }}-index-gateway
{{- end }}

{{/*
ruler fullname
*/}}
{{- define "loki-cluster.rulerFullname" -}}
{{ include "loki-cluster.fullname" . }}-ruler
{{- end }}

{{/*
compactor fullname
*/}}
{{- define "loki-cluster.compactorFullname" -}}
{{ include "loki-cluster.fullname" . }}-compactor
{{- end }}

{{/*
query-scheduler fullname
*/}}
{{- define "loki-cluster.querySchedulerFullname" -}}
{{ include "loki-cluster.fullname" . }}-query-scheduler
{{- end }}

{{/*
Return if deployment mode is simple scalable
*/}}
{{- define "loki-cluster.deployment.isScalable" -}}
  {{- and (eq (include "loki-cluster.isUsingObjectStorage" . ) "true") (or (eq .Values.deploymentMode "SingleBinary<->SimpleScalable") (eq .Values.deploymentMode "SimpleScalable") (eq .Values.deploymentMode "SimpleScalable<->Distributed")) }}
{{- end -}}

{{/*
Return if deployment mode is single binary
*/}}
{{- define "loki-cluster.deployment.isSingleBinary" -}}
  {{- or (eq .Values.deploymentMode "SingleBinary") (eq .Values.deploymentMode "SingleBinary<->SimpleScalable") }}
{{- end -}}

{{/*
Return if deployment mode is distributed
*/}}
{{- define "loki-cluster.deployment.isDistributed" -}}
  {{- and (eq (include "loki-cluster.isUsingObjectStorage" . ) "true") (or (eq .Values.deploymentMode "Distributed") (eq .Values.deploymentMode "SimpleScalable<->Distributed")) }}
{{- end -}}

{{/* Determine if deployment is using object storage */}}
{{- define "loki-cluster.isUsingObjectStorage" -}}
{{- or (eq .Values.loki.storage.type "gcs") (eq .Values.loki.storage.type "s3") (eq .Values.loki.storage.type "azure") (eq .Values.loki.storage.type "swift") (eq .Values.loki.storage.type "alibabacloud") -}}
{{- end -}}



{{/*
gateway common labels
*/}}
{{- define "loki-cluster.gatewayLabels" -}}
{{ include "loki-cluster.labels" . }}
app.kubernetes.io/component: gateway
{{- end }}
